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

    # Anthropic/Claude upstreams (native or OpenRouter-routed) — the only ones that honor an explicit
    # cache_control breakpoint. Everything else auto-caches server-side and would reject the field.
    ANTHROPIC_FAMILY = %r{(?:^|/)claude|(?:^|/)anthropic/}i

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

    # Force the tier's model; leave every other field (messages, tools, stream_options, …) untouched —
    # EXCEPT prompt-caching breakpoints, which we normalize against the ROUTED model (below). The client
    # only guessed the upstream; here we know it, so we own the caching decision authoritatively.
    def routed_body
      apply_cache_policy(body.merge("model" => model), model)
    end

    # [LevelCode] Prompt-caching policy on the routed body. For an Anthropic/Claude upstream, ensure a
    # cache_control breakpoint on the system message (caches tools+system) and the last message (caches the
    # transcript) so multi-turn agent runs are billed at the ~10x-cheaper cached rate — and this fires for
    # EVERY gateway client, including editors too old to send cache_control themselves. For any other
    # upstream, STRIP client-sent cache_control so a tier re-route (e.g. Claude → GPT) never forwards the
    # Anthropic-only field to a provider that would reject it. Idempotent (a block that already carries a
    # breakpoint is left as-is) and defensive: on any structural surprise it returns the body UNCHANGED, so
    # a bug here can never break the paying request — the worst case is "no caching", never "500". Kill
    # switch: set LEVELCODE_GATEWAY_CACHE=0 to revert to pure pass-through.
    def apply_cache_policy(routed, routed_model)
      return routed if ENV["LEVELCODE_GATEWAY_CACHE"] == "0"
      msgs = routed["messages"]
      return routed unless msgs.is_a?(Array) && msgs.any?

      out = msgs.map { |m| m.is_a?(Hash) ? m.dup : m }
      if ANTHROPIC_FAMILY.match?(routed_model.to_s)
        mark_cacheable!(out.find { |m| m.is_a?(Hash) && m["role"].to_s == "system" }) # tools + system
        mark_cacheable!(out.last)                                                     # transcript prefix
      else
        out.each { |m| strip_cache!(m) }
      end
      routed.merge("messages" => out)
    rescue StandardError => e
      Rails.logger.warn("[Levelcode::AiRouter] cache policy skipped: #{e.class}: #{e.message}")
      routed
    end

    # Put a cache_control breakpoint on a message's last content block (converting a plain string to a
    # single text block). Idempotent — a last block that already has cache_control is left untouched; no-op
    # on nil/empty content. Clones the content array/blocks so the caller's body is never mutated in place.
    def mark_cacheable!(msg)
      return unless msg.is_a?(Hash)
      content = msg["content"]
      if content.is_a?(String)
        return if content.empty?
        msg["content"] = [ { "type" => "text", "text" => content, "cache_control" => { "type" => "ephemeral" } } ]
      elsif content.is_a?(Array) && content.any?
        dup = content.map { |b| b.is_a?(Hash) ? b.dup : b }
        last = dup.last
        last["cache_control"] = { "type" => "ephemeral" } if last.is_a?(Hash) && !last.key?("cache_control")
        msg["content"] = dup
      end
    end

    # Remove any client-sent cache_control (routed to a non-Anthropic upstream that would reject it).
    def strip_cache!(msg)
      return unless msg.is_a?(Hash)
      content = msg["content"]
      return unless content.is_a?(Array)
      msg["content"] = content.map { |b| b.is_a?(Hash) ? b.except("cache_control") : b }
    end
  end
end
