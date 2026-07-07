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
      request = build_request(uri, body.merge("stream" => true, "stream_options" => stream_opts))

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
      request = build_request(uri, body.merge("stream" => false))
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
      request["HTTP-Referer"] = ENV["SITE_ORIGIN"] if ENV["SITE_ORIGIN"].present?
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

    def read_error_body(response)
      response.read_body
    rescue IOError, StandardError
      nil
    end
  end
end
