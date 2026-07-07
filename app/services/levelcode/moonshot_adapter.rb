module Levelcode
  # Stub adapter for Moonshot's native API (M-G7). Interface-compatible with
  # Levelcode::OpenRouterAdapter but not wired until the `orbits_moonshot_native`
  # flag is flipped (SPEC §7, §11). Kimi is reachable today via OpenRouter, so
  # this exists only to lock the interface.
  class MoonshotAdapter
    Result = OpenRouterAdapter::Result

    def self.enabled?
      ENV["LEVELCODE_MOONSHOT_NATIVE"] == "true"
    end

    def initialize(api_key: ENV["MOONSHOT_API_KEY"])
      @api_key = api_key
    end

    def stream(_body, on_chunk:)
      raise NotImplementedError, "Levelcode::MoonshotAdapter is a stub (M-G7); use OpenRouterAdapter"
    end

    def complete(_body)
      raise NotImplementedError, "Levelcode::MoonshotAdapter is a stub (M-G7); use OpenRouterAdapter"
    end
  end
end
