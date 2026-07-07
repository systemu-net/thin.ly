module Levelcode
  # Picks the upstream adapter and streams the OpenAI-compatible completion through
  # transparently (SPEC §7). The EFFECTIVE MODEL is decided by the caller from the
  # user's tier (Levelcode.gateway_model) and passed in — the router never lets the
  # request's own `model` field pick a pricier engine than the plan allows.
  #
  #   Levelcode::AiRouter.call(body, model:, on_chunk:)
  #
  # `on_chunk` receives each raw SSE `data:` payload verbatim. Returns the adapter
  # Result (usage + effective model).
  class AiRouter
    # Fallback only — the caller always passes an explicit model.
    DEFAULT_MODEL = ENV.fetch("LEVELCODE_MODEL", "moonshotai/kimi-k2.7-code").freeze

    def self.call(body, model:, on_chunk:)
      new(body, model: model).call(on_chunk: on_chunk)
    end

    def self.complete(body, model:)
      new(body, model: model).complete
    end

    def initialize(body, model:)
      @body = body
      @model = model.presence || DEFAULT_MODEL
    end

    def call(on_chunk:)
      adapter.stream(routed_body, on_chunk: on_chunk)
    end

    def complete
      adapter.complete(routed_body)
    end

    private

    attr_reader :body, :model

    def adapter
      @adapter ||=
        if defined?(MoonshotAdapter) && MoonshotAdapter.enabled? && model.to_s.start_with?("moonshotai/")
          MoonshotAdapter.new
        else
          OpenRouterAdapter.new
        end
    end

    # Force the tier's model; leave every other field (messages, tools,
    # stream_options, …) untouched.
    def routed_body
      body.merge("model" => model)
    end
  end
end
