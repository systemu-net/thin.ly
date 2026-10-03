require "net/http"
require "json"

module Levelcode
  # Streams OpenRouter's OpenAI-compatible /api/v1/chat/completions endpoint.
  #
  # This is a *transparent* proxy adapter (SPEC §4/§7): it yields each raw SSE
  # `data:` line verbatim to the caller (which forwards it to the editor
  # unchanged) and only peeks at the final `usage` object so the gateway can
  # tee it into metering.
  class OpenRouterAdapter
    BASE_URL = "https://openrouter.ai/api/v1/chat/completions".freeze
    OPEN_TIMEOUT = 15  # seconds
    READ_TIMEOUT = 300 # seconds — long-lived streams

    Result = Struct.new(:usage, :model, keyword_init: true)

    # OpenRouter provider routing for the FREE model (gpt-oss). OpenRouter's "WandB" provider
    # mishandles the gpt-oss "harmony" format and 401s with "Unknown role: final", so pin the free
    # model to reliable providers and exclude WandB. Scoped to the free model; paid models get a PRICE
    # ceiling instead (with_provider_routing). If WandB reappears, verify the `ignore` slug against
    # OpenRouter's provider list / Activity log.
    FREE_MODEL_PROVIDER = {
      "order" => %w[fireworks together deepinfra],
      "ignore" => %w[wandb],
      "allow_fallbacks" => true
    }.freeze

    def initialize(api_key: ENV["OPENROUTER_API_KEY"] || Rails.application.credentials.fetch(:openrouter_api_key))
      @api_key = api_key
    end

    # Streams the upstream response.
    #
    # body      — the OpenAI chat body (Hash) to POST upstream.
    # on_chunk: — called with each raw SSE `data:` payload string (the JSON
    #             between `data: ` and the delimiter). `[DONE]` is NOT yielded;
    #             the caller emits its own terminator.
    #
    # Returns an Levelcode::OpenRouterAdapter::Result with the final usage Hash
    # (or nil if the upstream never sent one).
    def stream(body, on_chunk:)
      uri = URI(BASE_URL)
      # Force usage reporting server-side so metering NEVER depends on the client
      # sending stream_options.include_usage — OpenAI-shaped upstreams omit the
      # final usage chunk otherwise, and the request would consume tokens unmetered
      # (cap bypass + under-billing). Preserve any client-supplied stream_options.
      stream_opts = (body["stream_options"] || body[:stream_options] || {}).merge("include_usage" => true)
      request = build_request(uri, with_provider_routing(body).merge("stream" => true, "stream_options" => stream_opts))

      usage = nil
      model = body["model"] || body[:model]

      http(uri).request(request) do |response|
        unless response.code.to_i == 200
          raise UpstreamError.new(response.code.to_i, read_error_body(response))
        end

        buffer = +""
        response.read_body do |segment|
          buffer << segment
          # SSE events are separated by a blank line; process complete lines.
          while (newline = buffer.index("\n"))
            line = buffer.slice!(0..newline).chomp
            next if line.empty?
            next unless line.start_with?("data:")

            payload = line.delete_prefix("data:").strip
            next if payload.empty?
            break if payload == "[DONE]"

            # A terminal error frame can arrive MID-STREAM, after the 200 OK (provider
            # outage, upstream rate-limit, mid-generation credit exhaustion). Raise the
            # SAME UpstreamError as a pre-stream non-200 so the controller sanitizes it
            # through one boundary and aborts — the raw frame is NEVER teed to the client.
            if (code = error_frame_status(payload))
              raise UpstreamError.new(code, payload)
            end

            usage = extract_usage(payload) || usage
            on_chunk.call(payload)
          end
        end
      end

      Result.new(usage: usage, model: model)
    end

    # Non-streaming pass-through. Returns the parsed upstream JSON Hash.
    def complete(body)
      uri = URI(BASE_URL)
      request = build_request(uri, with_provider_routing(body).merge("stream" => false))
      response = http(uri).request(request)

      unless response.code.to_i == 200
        raise UpstreamError.new(response.code.to_i, response.body)
      end

      JSON.parse(response.body)
    end

    class UpstreamError < StandardError
      attr_reader :status, :body

      def initialize(status, body)
        @status = status
        @body = body
        super("OpenRouter upstream returned #{status}")
      end
    end

    private

    # Shape the upstream `provider` preference for the routed model.
    #
    #   free model (gpt-oss) → FREE_MODEL_PROVIDER, unless the client sent its own preference.
    #   any other catalog row → a PRICE CEILING at that row's catalog rate, merged ON TOP of whatever the
    #                           client sent (a client may steer routing; it may not lift the ceiling).
    #   off-catalog / Moonshot-native → untouched.
    #
    # WHY THE CEILING. Metering bills a request at the catalog rate (Levelcode.cost_micros) and never
    # reads what OpenRouter actually charged. OpenRouter, left to route freely, spreads one model over
    # endpoints priced up to 2x that rate — GPT-6 Astra runs $5/$25 (Flex) through $20/$100 (Fast), and
    # Opus 4.8 has an Anthropic "fast" tier at $10/$50 against our $5/$25. Routed there, we under-bill by
    # half and cannot see it. `max_price` makes wire cost <= billed cost by construction.
    #
    # It is a HARD filter: OpenRouter refuses the request outright if no endpoint fits, rather than
    # quietly running it over price. That is the safe money direction — the same direction rate_for
    # takes for an off-catalog id — and it turns a stale catalog price into a loud 4xx instead of a
    # silent loss. Units line up without conversion: OpenRouter reads max_price in $/M tokens, and a
    # catalog rate is micro-$/token, which is the same number.
    #
    # The FREE model is deliberately NOT ceilinged: its catalog row ($0.03/$0.15) sits below its listed
    # endpoints ($0.04/$0.17), so a ceiling would exclude every endpoint and take the free tier down.
    def with_provider_routing(body)
      model = (body["model"] || body[:model]).to_s
      if model.include?("gpt-oss")
        return body if body.key?("provider") || body.key?(:provider)

        return body.merge("provider" => FREE_MODEL_PROVIDER)
      end

      ceiling = price_ceiling(model)
      return body unless ceiling

      # Exactly one string-keyed "provider" goes out, whatever the caller sent. A symbol-keyed body
      # would otherwise serialise :provider beside "provider" (and :max_price beside "max_price"), and
      # which of the two OpenRouter honours would be down to its parser — the ceiling would hold or
      # not by accident. A preference that is not an object is dropped rather than raised on: the
      # ceiling is the part that has to survive, and a 500 here would be ours, not upstream's.
      client = body["provider"] || body[:provider]
      client = client.is_a?(Hash) ? client.transform_keys(&:to_s).except("max_price") : {}
      body.except(:provider).merge("provider" => client.merge("max_price" => ceiling))
    end

    # `{"prompt" => $/M, "completion" => $/M}` for a catalog model, nil for anything else.
    def price_ceiling(model)
      row = Levelcode::ModelCatalog.find(model)
      return nil unless row

      { "prompt" => row[:input].to_f, "completion" => row[:output].to_f }
    end

    def http(uri)
      client = Net::HTTP.new(uri.host, uri.port)
      client.use_ssl = uri.scheme == "https"
      client.open_timeout = OPEN_TIMEOUT
      client.read_timeout = READ_TIMEOUT
      client
    end

    def build_request(uri, body)
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "application/json"
      request["Accept"] = "text/event-stream"
      # OpenRouter attribution headers (optional but recommended).
      # Attribution: OpenRouter groups spend by app using HTTP-Referer. This was conditional on
      # SITE_ORIGIN being set — and it isn't in production — so every gateway generation logged as
      # "Unknown" and our OpenRouter spend couldn't be broken out by app. Fall back to the same default
      # the controller already uses (site_origin) so attribution works with or without the env var.
      request["HTTP-Referer"] = ENV["SITE_ORIGIN"].presence || "https://levelcode.ai"
      request["X-Title"] = "LevelCode"
      request.body = JSON.generate(body)
      request
    end

    # Pulls the `usage` object out of a chunk if present, without reshaping the
    # chunk itself. Returns a Hash or nil.
    def extract_usage(payload)
      parsed = JSON.parse(payload)
      parsed["usage"]
    rescue JSON::ParserError
      nil
    end

    # If a chunk is a terminal error frame (`{"error":{...}}`), return its numeric
    # status (or 0 when none — the controller's classifier maps 0 to the generic
    # our-side message). Returns nil for a normal content chunk.
    def error_frame_status(payload)
      parsed = JSON.parse(payload)
      return nil unless parsed.is_a?(Hash) && parsed["error"].present?

      parsed.dig("error", "code").to_i
    rescue JSON::ParserError, TypeError
      nil
    end

    def read_error_body(response)
      response.read_body
    rescue IOError, StandardError
      nil
    end
  end
end
