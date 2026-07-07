# frozen_string_literal: true

# Levelcode — LevelCode managed-hosting namespace (SPEC §1, §6).
#
# This file is the EXPLICIT definition of the `Levelcode` module for Zeitwerk. It
# must live at lib/levelcode.rb (not lib/levelcode/plans.rb) so that autoloading maps
# lib/levelcode.rb -> Levelcode; the child constants (Levelcode::EditorToken, ::AiRouter,
# ::Metering, ::WebhookSync, …) are provided by app/services/levelcode/*.rb.
module Levelcode
  # Product tag for every Levelcode (LevelCode) subscription / wallet / usage row.
  PRODUCT = "levelcode"

  # Server-side source of truth for the four managed-hosting tiers.
  #
  # Caps are tokens/month and prices are cents (SPEC §6, DECISIONS D10):
  #   pro 15M/2M, pro_plus 35M/4.5M, max 55M/7M, ultra 95M/12M;
  #   $20 / $40 / $60 / $100.
  #
  # The frontend never hard-codes any of this — `GET /pricing` surfaces it.
  PLANS = [
    {
      key: "orbits_pro",
      name: "Pro",
      price_cents: 2_000,
      interval: "month",
      input_cap: 15_000_000,
      output_cap: 2_000_000,
      turns: 375,
      stripe_lookup_key: "orbits_pro",
      features: [
        "~375 agent turns / month",
        "15M input · 2M output tokens",
        "Kimi K2.7 Code gateway",
        "Bring-your-own-key always free"
      ]
    },
    {
      key: "orbits_pro_plus",
      name: "Pro+",
      price_cents: 4_000,
      interval: "month",
      input_cap: 35_000_000,
      output_cap: 4_500_000,
      turns: 875,
      stripe_lookup_key: "orbits_pro_plus",
      features: [
        "~875 agent turns / month",
        "35M input · 4.5M output tokens",
        "Kimi K2.7 Code gateway",
        "Priority routing"
      ]
    },
    {
      key: "orbits_max",
      name: "Max",
      price_cents: 6_000,
      interval: "month",
      input_cap: 55_000_000,
      output_cap: 7_000_000,
      turns: 1_375,
      stripe_lookup_key: "orbits_max",
      features: [
        "~1,375 agent turns / month",
        "55M input · 7M output tokens",
        "Kimi K2.7 Code gateway",
        "Priority routing"
      ]
    },
    {
      key: "orbits_ultra",
      name: "Ultra",
      price_cents: 10_000,
      interval: "month",
      input_cap: 95_000_000,
      output_cap: 12_000_000,
      turns: 2_375,
      stripe_lookup_key: "orbits_ultra",
      features: [
        "~2,375 agent turns / month",
        "95M input · 12M output tokens",
        "Kimi K2.7 Code gateway",
        "Highest priority routing"
      ]
    }
  ].freeze

  # Default model keys (mirror the backend ENV defaults in SPEC §1). These MUST be
  # real OpenRouter slugs — an unknown id makes every gateway request 400. (The
  # earlier "kimi-k2.6"/"kimi-k2.6-small" placeholders don't exist on OpenRouter.)
  DEFAULT_MODEL = "moonshotai/kimi-k2.7-code"
  # There is NO genuinely-smaller Kimi — `kimi-latest` is an unstable alias to the
  # newest model (often as pricey as, or pricier than, the flagship), so it's the
  # wrong "cheap request" target. Default the small/cheap path to the flagship;
  # override LEVELCODE_SMALL_MODEL to route trivial completions to a real cheaper model.
  DEFAULT_SMALL_MODEL = DEFAULT_MODEL

  # ── Free tier (M11) — logged-in, not-yet-paid users get the gateway on a cheap
  # open-weights engine (gpt-oss-120b: ~$0.03/M in · $0.15/M out — ~25× cheaper
  # than the flagship). Metered against a hard monthly cap; over-cap → upgrade CTA.
  FREE_PLAN_KEY = "free"
  FREE_MODEL = ENV.fetch("LEVELCODE_FREE_MODEL", "openai/gpt-oss-120b").freeze
  # Tunable via ENV (economics TBD). Lean-ish default: ~5M in / 1M out per month
  # (~300–400 12K-context agent turns + inline completions).
  FREE_INPUT_CAP  = ENV.fetch("LEVELCODE_FREE_INPUT_CAP", 5_000_000).to_i
  FREE_OUTPUT_CAP = ENV.fetch("LEVELCODE_FREE_OUTPUT_CAP", 1_000_000).to_i
  # Per-request output ceiling for the free tier (a throttle): the monthly cap is checked
  # per-request-start, so without this a burst of concurrent streams could each request a
  # huge max_tokens and overshoot the cap before the counters catch up. Generous enough for
  # normal chat/agent turns; the editor's default is 4096.
  FREE_MAX_TOKENS = ENV.fetch("LEVELCODE_FREE_MAX_TOKENS", 8_192).to_i
  # Per-request output ceiling for PAID plans (M14). Enforcement is per-request-start, so without a
  # per-request bound a burst of concurrent streams could overshoot the DOLLAR budget before the
  # counters land. Generous for agent turns; bounds a single request's cost. Matters most once a
  # frontier model (Opus/Fable) is confirmed-live — a single unclamped huge request would cost dollars.
  PAID_MAX_TOKENS = ENV.fetch("LEVELCODE_PAID_MAX_TOKENS", 32_768).to_i

  # The "Auto" pseudo-model the editor can request — the gateway routes each turn to the cheapest
  # engine that fits (free margin, rec #4). Reachable on any plan (free stays on gpt-oss anyway).
  AUTO_MODEL = "auto"
  # A turn is "trivial" (→ cheap engine) when it carries no tools and little input text.
  AUTO_TRIVIAL_CHARS = ENV.fetch("LEVELCODE_AUTO_TRIVIAL_CHARS", 4_000).to_i

  class << self
    # Look up a single plan definition by its key (e.g. "orbits_pro").
    def plan(key)
      PLANS.find { |p| p[:key] == key.to_s }
    end

    # Per-model token rates, expressed in **micro-dollars per token**
    # (equivalently: $/M tokens, since $1/M == 1 micro-dollar/token).
    #
    # Real OpenRouter list prices (verified): kimi-k2.7-code $0.74/M in · $3.50/M
    # out · $0.15/M cached; kimi-latest $0.66/M in · $3.41/M out · $0.14/M cached.
    # NOTE: the plan caps/prices in PLANS were sized against the old ~$0.66/$3.41
    # assumption — re-check margins now that the flagship is a touch pricier.
    # Per-model {input:, cached_input:, output:} micro-$/token rates — derived from the ONE roster
    # definition (Levelcode::ModelCatalog). An unknown model falls back to the flagship's rate in
    # cost_micros. Verify the frontier rows' `status: :assumption` prices before billing on them.
    def rate_table
      Levelcode::ModelCatalog.rate_table
    end

    # The plan's DEFAULT gateway model, used when the request doesn't name a reachable one
    # (paid → flagship, free → open-weights).
    def default_model(plan_key)
      plan_tier(plan_key) == :free ? FREE_MODEL : DEFAULT_MODEL
    end

    # "Auto" routing: send trivial turns (no tools + small input) to the cheap open-weights engine,
    # standard/agent turns to the plan default. Both targets are always live + entitled, so this
    # never over-reaches the plan; it only ever routes DOWN in cost.
    def auto_route(plan_key, body)
      return default_model(plan_key) if body["tools"].present? # agent/tool turns need the strong model

      message_chars(body["messages"]) <= AUTO_TRIVIAL_CHARS ? FREE_MODEL : default_model(plan_key)
    end

    # Total characters of message content — defensively. `body` is a CLIENT-CONTROLLED transparent
    # proxy payload with NO shape validation, so `messages` may be a bare object, contain scalars, or
    # carry array (multimodal) content. Never raise: a malformed body must not 500 the gateway. Any
    # oddity falls back toward the larger count (→ the strong model), which is the safe cost direction.
    def message_chars(messages)
      list = messages.is_a?(Array) ? messages : [ messages ]
      list.sum { |m| m.is_a?(Hash) ? content_length(m["content"]) : 0 }
    end

    # Length of a single message's `content`. A String → its length. A multimodal parts array →
    # the sum of text-part lengths, but ANY non-text part (image/audio) forces the turn past the
    # trivial threshold so vision/audio turns always route to the strong model. Anything else → 0.
    def content_length(content)
      case content
      when String then content.length
      when Array
        content.sum do |part|
          if part.is_a?(Hash) && (part["type"].nil? || part["type"] == "text")
            part["text"].to_s.length
          else
            AUTO_TRIVIAL_CHARS + 1 # image/audio/unknown part → not trivial → strong model
          end
        end
      else 0
      end
    end

    # Live-REACHABLE roster for a plan: the models it's entitled to (by tier) that ALSO carry a
    # CONFIRMED price — we never meter/bill against an assumed price. As frontier prices are confirmed
    # in ModelCatalog they auto-go-live here. Free → [gpt-oss]; paid → [Kimi, gpt-oss] today, widening
    # as prices land. Entitlement stays server-side: a free user can never reach the flagship.
    def allowed_models(plan_key)
      entitled_models(plan_key).select { |id| Levelcode::ModelCatalog.find(id)&.dig(:status) == :confirmed }
    end

    # The EFFECTIVE gateway model: the requested model iff it's reachable for the plan, else the
    # plan default. Under the DOLLAR-budget scheme (M14) any reachable model is safe — it burns the
    # plan's budget at its real cost — so this is entitlement, not price-protection.
    def gateway_model(plan_key, requested = nil)
      req = requested.to_s
      allowed_models(plan_key).include?(req) ? req : default_model(plan_key)
    end

    # Compute the durable-ledger cost of a single request in micro-dollars.
    #
    #   model  — upstream model id (falls back to the default model's rates)
    #   input  — prompt tokens billed at the full input rate
    #   output — completion tokens
    #   cached — cached-input tokens billed at the cheaper cached rate; these
    #            are a subset of `input`, so the non-cached remainder is billed
    #            at the full input rate.
    #
    # Returns a rounded integer (micro-dollars).
    def cost_micros(model, input, output, cached = 0)
      table = rate_table
      rate = table[model.to_s] || table[DEFAULT_MODEL]

      input = input.to_i
      output = output.to_i
      cached = cached.to_i.clamp(0, input)
      billed_input = input - cached

      micros =
        (billed_input * rate[:input]) +
        (cached * rate[:cached_input]) +
        (output * rate[:output])

      micros.round
    end

    # ── Credit economics (M14) ──────────────────────────────────────────────
    # DISPLAY layer over the roster. The plan allowance is a DOLLAR budget (budget_micros); every
    # model burns it at its real per-request cost. Multipliers/turns below are a UI convenience that
    # reproduces the pricing table from prices — the ledger is always metered in dollars.

    # OpenRouter's top-up fee on routed traffic (~5.5%). Folded into the plan budget so the published
    # dollar allowance already covers it; move to direct provider keys at volume to shed it.
    ROUTING_FEE = 1.055

    # Plan key → catalog tier symbol (drives which roster models the plan may reach).
    def plan_tier(plan_key)
      case plan_key.to_s
      when "orbits_ultra"    then :ultra
      when "orbits_max"      then :max
      when "orbits_pro_plus" then :pro_plus
      when "orbits_pro"      then :pro
      else :free
      end
    end

    # The roster model ids a plan may use through the gateway (its tier ⊇ the model's min_tier).
    def entitled_models(plan_key)
      Levelcode::ModelCatalog.entitled(plan_tier(plan_key))
    end

    # A plan's DOLLAR compute budget (micro-$/month) — DERIVED as the flagship (Kimi) worst-case:
    # the full token allowance run at the flagship rate with 50% input cache, plus the routing fee.
    # This is the dollar allowance every model burns; the credit scheme makes worst-case margin
    # identical for any model mix (see docs, M14).
    def budget_micros(plan_key)
      p = plan(plan_key)
      return 0 unless p

      rate = Levelcode::ModelCatalog.find(DEFAULT_MODEL)
      in_cap = p[:input_cap].to_i
      out_cap = p[:output_cap].to_i
      cached = in_cap / 2
      billed = in_cap - cached
      raw = (billed * rate[:input]) + (cached * rate[:cached_input]) + (out_cap * rate[:output])
      (raw * ROUTING_FEE).round
    end

    # The free tier's DOLLAR budget (micro-$): its token caps run on the open-weights engine
    # (worst case, no cache credit) — ~$0.30/mo. This is the hard ceiling free users burn.
    # FREE_MODEL is ENV-overridable, so fall back to the canonical gpt-oss rates if the override
    # isn't in the catalog (never crash free-wallet provisioning on a config typo).
    def free_budget_micros
      rate = Levelcode::ModelCatalog.find(FREE_MODEL) || Levelcode::ModelCatalog.find("openai/gpt-oss-120b")
      (FREE_INPUT_CAP * rate[:input] + FREE_OUTPUT_CAP * rate[:output]).round
    end

    # Credit multiplier for a model (cost relative to the flagship) — derived, DISPLAY only.
    def model_multiplier(model)
      Levelcode::ModelCatalog.multiplier(model)
    end

    # How many reference turns a plan's budget buys on a model (budget ÷ per-turn cost incl. routing).
    def turns_for(plan_key, model)
      turns_in_budget(budget_micros(plan_key), model)
    end

    # How many reference turns a given DOLLAR balance buys on a model (used for "≈ N turns left").
    def turns_in_budget(budget, model)
      per_turn = Levelcode::ModelCatalog.reference_cost_micros(model) * ROUTING_FEE
      return 0 if per_turn <= 0

      (budget.to_i / per_turn).floor
    end

    # The plan's model roster for the picker/dashboard: every ENTITLED model with its display
    # economics and, when `remaining_micros` is given, how many more turns the current balance buys.
    # `live` = actually reachable (confirmed price); staged (assumption-priced) models are shown but
    # not selectable/billable. This is the ONE surface the editor + dashboard render.
    def roster_for(plan_key, remaining_micros = nil)
      live = allowed_models(plan_key)
      entitled_models(plan_key).map do |id|
        m = Levelcode::ModelCatalog.find(id)
        {
          id: id,
          label: m[:label],
          context: m[:context],
          multiplier: model_multiplier(id),
          live: live.include?(id),
          turns_budget: turns_for(plan_key, id),
          turns_left: remaining_micros.nil? ? nil : turns_in_budget(remaining_micros, id)
        }
      end
    end
  end
end
