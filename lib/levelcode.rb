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
      turns: 260,
      stripe_lookup_key: "orbits_pro",
      features: [
        "2,000 credits/mo · ~260 Kimi turns, or ~39 on Opus 4.8",
        "Usage that refreshes through your billing cycle",
        "Kimi K2.7 Code + Opus 4.8",
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
      turns: 520,
      stripe_lookup_key: "orbits_pro_plus",
      features: [
        "4,000 credits/mo · ~520 Kimi turns, or ~78 on Opus 4.8",
        "Usage that refreshes through your billing cycle",
        "Kimi K2.7 Code + Opus 4.8",
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
      turns: 780,
      stripe_lookup_key: "orbits_max",
      features: [
        "6,000 credits/mo · ~780 Kimi turns, or ~117 on Opus 4.8",
        "Usage that refreshes through your billing cycle",
        "Kimi K2.7 Code + Opus 4.8",
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
      turns: 1_300,
      stripe_lookup_key: "orbits_ultra",
      features: [
        "10,000 credits/mo · ~1,300 Kimi turns, or ~195 on Opus 4.8",
        "Usage that refreshes through your billing cycle",
        "Kimi K2.7 Code + Opus 4.8",
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

  # Target model-COGS as a fraction of subscription revenue → the enforced monthly credit budget is
  # `plan price × CREDIT_COGS_RATIO`. Gross margin = 1 - this (before Stripe/infra). Because metering
  # charges each model its REAL per-token cost, this margin holds for ANY model mix — pricey models
  # (Opus ≈ 7× Kimi) just burn the budget faster. ENV-tunable so pricing can move without a deploy.
  CREDIT_COGS_RATIO = ENV.fetch("LEVELCODE_CREDIT_COGS_RATIO", 0.50).to_f

  # The in-product spending unit. Balances are SHOWN in credits, never dollars: $1 = 100 credits, so
  # 1 credit = $0.01 = 10_000 micro-$.
  #
  # This is PRESENTATION ONLY. The ledger, metering, Stripe prices, and invoices all stay in
  # micro-dollars, because dollars are what providers charge us and what we actually bill — and
  # re-denominating stored balances would put Stripe reconciliation at risk for no gain. Credits exist
  # for a behavioural reason: a shrinking DOLLAR balance reads as money being lost, while credits read
  # as an allowance meant to be spent.
  #
  # Because a plan's retail budget equals its price (budget_micros == price × CREDIT_COGS_RATIO, and
  # retail divides that ratio back out), a plan's credit allowance is exactly its price in CENTS:
  # $20 Pro → 2_000 credits, $100 Ultra → 10_000 credits. See #plan_credits.
  CREDITS_PER_DOLLAR = 100
  MICROS_PER_CREDIT = 1_000_000 / CREDITS_PER_DOLLAR   # 10_000 micro-$ == 1 credit

  # Time-released budget tranches (rolling usage windows). When > 1, the enforced ceiling rises in N
  # equal steps from budget/N up to the full budget across the billing period (window = period / N), so
  # a heavy user cannot drain the whole month on day one while a light user never notices. N = 1
  # DISABLES tranching (ceiling == full budget from day one) — the SAFE DEFAULT, so this ships inert
  # until the usage dashboard (Phase 2) and product sign-off land; set LEVELCODE_BUDGET_TRANCHES=3 to
  # activate. NEVER applied to the free tier. See Metering.unlocked_budget_micros.
  BUDGET_TRANCHES = ENV.fetch("LEVELCODE_BUDGET_TRANCHES", 1).to_i

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
    # Returns a rounded integer (micro-dollars), INCLUSIVE of the OpenRouter routing fee — this is the
    # true wire cost, so the enforced dollar budget is spent at the real rate and the target margin
    # (1 − CREDIT_COGS_RATIO) holds. Callers should pass the ROUTED catalog model id (what we intend to
    # charge); an unknown id falls back to the most expensive confirmed rate so it can never under-bill.
    def cost_micros(model, input, output, cached = 0)
      rate = rate_for(model)

      input = input.to_i
      output = output.to_i
      cached = cached.to_i.clamp(0, input)
      billed_input = input - cached

      micros =
        (billed_input * rate[:input]) +
        (cached * rate[:cached_input]) +
        (output * rate[:output])

      (micros * ROUTING_FEE).round
    end

    # The per-token rate row for a model id. A KNOWN catalog id → its own rate. An UNKNOWN id (an
    # upstream-substituted slug, or a dated snapshot the caller didn't normalize) → the most expensive
    # CONFIRMED rate, so an off-catalog id never UNDER-bills (the safe money direction). This is why the
    # gateway bills at the ROUTED catalog model, not the upstream-reported string.
    def rate_for(model)
      rate_table[model.to_s] || Levelcode::ModelCatalog.max_confirmed_rate
    end

    # Rough tokens-per-character used to estimate input size for the admission-time budget reservation.
    CHARS_PER_TOKEN = 4

    # Worst-case cost (micro-$) of a request BEFORE it runs — for the admission-time budget reservation
    # (M14 concurrency guard). Estimates input tokens from the body's character count (≈ CHARS_PER_TOKEN
    # chars/token, clamped to the model's context window) and assumes the full per-request output
    # ceiling. Deliberately conservative (reserves high, never caches); the real cost reconciles the
    # reservation DOWN on settle. `model` must be the routed catalog id (its rate + context window).
    def estimate_cost_micros(model, body, free_tier: false)
      body ||= {}
      ctx = (Levelcode::ModelCatalog.find(model.to_s) || {})[:context].to_i
      est_input = (message_chars(body["messages"]).to_f / CHARS_PER_TOKEN).ceil
      est_input = [ est_input, ctx ].min if ctx.positive?

      ceiling = free_tier ? FREE_MAX_TOKENS : PAID_MAX_TOKENS
      requested_out = [ body["max_tokens"], body["max_completion_tokens"] ].compact.map(&:to_i).select(&:positive?).min
      est_output = requested_out ? [ requested_out, ceiling ].min : ceiling

      cost_micros(model, est_input, est_output, 0)
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

    # A plan's DOLLAR compute budget (micro-$/month) — a fixed fraction of subscription revenue
    # (CREDIT_COGS_RATIO). Every model burns this same allowance at its real per-request wire cost
    # (cost_micros already includes the routing fee), so the target margin (1 − CREDIT_COGS_RATIO)
    # holds for any model mix (see docs, M14).
    def budget_micros(plan_key)
      p = plan(plan_key)
      return 0 unless p

      # Revenue-based (Cursor-style): the monthly credit allowance is a fixed fraction of the plan's
      # price, so gross margin = 1 - CREDIT_COGS_RATIO regardless of which models the user picks.
      # micro-$ = dollars × 1_000_000; price_cents / 100 = dollars of revenue.
      (p[:price_cents] / 100.0 * CREDIT_COGS_RATIO * 1_000_000).round
    end

    # Convert an internal COST-denominated micro-$ figure (the unit the wallet budget + metering are
    # enforced in — what a request actually costs at the wire) into the RETAIL micro-$ the CUSTOMER
    # sees, i.e. what they PAID. Because a paid plan's budget_micros == price × CREDIT_COGS_RATIO,
    # dividing by the ratio yields the price; spent/remaining scale the same way, so the gross margin
    # is preserved and "≈ turns left" (computed from the cost balance) is unchanged — only the dollar
    # headline on the dashboard rises from the cost budget to the amount actually paid. The free tier
    # has no price (its budget is a raw cost figure), so it is shown as-is.
    def retail_micros(cost_micros, plan_key)
      return cost_micros.to_i if plan_key.blank? || plan_key.to_s == FREE_PLAN_KEY || CREDIT_COGS_RATIO <= 0

      (cost_micros.to_f / CREDIT_COGS_RATIO).round
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

    # How many reference turns a plan's FULL monthly allowance buys on a model.
    def turns_for(plan_key, model)
      turns_in_retail_budget(retail_micros(budget_micros(plan_key), plan_key),
                             retail_per_turn_micros(plan_key, model))
    end

    # What ONE reference turn costs on a model, in COST micro-$ (real wire cost incl. the routing fee).
    # Rounded to a whole micro-dollar like cost_micros: the name says micro-$, and keeping it an Integer
    # stops a float from propagating into the turn counts below (PR #380 review).
    def per_turn_cost_micros(model)
      (Levelcode::ModelCatalog.reference_cost_micros(model) * ROUTING_FEE).round
    end

    # What one turn costs at RETAIL — the unit the customer's balance is shown in. THE single definition
    # of the per-turn figure: the dashboard prints it, and both turn counts below divide by it.
    def retail_per_turn_micros(plan_key, model)
      retail_micros(per_turn_cost_micros(model), plan_key).round
    end

    # How many reference turns a RETAIL balance buys at a RETAIL per-turn price.
    #
    # Both arguments must already be retail integers. That is the whole point (PR #380 review): the
    # dashboard shows "N credits/turn" beside "≈ turns left", and a user divides one into the other by
    # eye. Previously turns came from COST micro-$ while the per-turn figure was ROUNDED RETAIL, so the
    # two rounded independently and disagreed for ~12% of balances (measured: 3,440 of 28,000 sampled).
    # Deriving both from the same rounded retail figure makes them agree by construction rather than by
    # coincidence. The margin ratio cancels in the division, so the counts themselves are unchanged.
    def turns_in_retail_budget(retail_budget, retail_per_turn)
      per_turn = retail_per_turn.to_i
      return 0 if per_turn <= 0

      retail_budget.to_i / per_turn
    end

    # RETAIL micro-$ → credits (the unit the customer sees). Display only — see CREDITS_PER_DOLLAR.
    def micros_to_credits(retail_micros)
      retail_micros.to_f / MICROS_PER_CREDIT
    end

    # A plan's monthly credit allowance. Derived, not hard-coded: the retail budget IS the plan price,
    # so this comes out to the price in cents ($100 Ultra → 10_000 credits).
    def plan_credits(plan_key)
      micros_to_credits(retail_micros(budget_micros(plan_key), plan_key)).round
    end

    # The plan's model roster for the picker/dashboard: every ENTITLED model with its display
    # economics and, when `remaining_micros` is given, how many more turns the current balance buys.
    # `live` = actually reachable (confirmed price); staged (assumption-priced) models are shown but
    # not selectable/billable. This is the ONE surface the editor + dashboard render.
    def roster_for(plan_key, remaining_micros = nil)
      live = allowed_models(plan_key)
      # Convert the balances ONCE, up front, so every row divides the same retail figures.
      retail_budget = retail_micros(budget_micros(plan_key), plan_key)
      retail_remaining = remaining_micros.nil? ? nil : retail_micros(remaining_micros, plan_key)
      entitled_models(plan_key).map do |id|
        m = Levelcode::ModelCatalog.find(id)
        per_turn = retail_per_turn_micros(plan_key, id)
        {
          id: id,
          label: m[:label],
          context: m[:context],
          multiplier: model_multiplier(id),
          live: live.include?(id),
          # What one turn costs at RETAIL, in micro-$ — the same unit as the balance fields, so the
          # dashboard converts both with one helper and "N credits/turn" divides into the balance
          # exactly. Derived from the SAME per-turn cost as turns_left, so the two always agree.
          per_turn_micros: per_turn,
          turns_budget: turns_in_retail_budget(retail_budget, per_turn),
          turns_left: remaining_micros.nil? ? nil : turns_in_retail_budget(retail_remaining, per_turn)
        }
      end
    end
  end
end
