# frozen_string_literal: true

module Levelcode
  # The Cursor-class model roster for the LevelCode Cloud gateway — the single source of truth for
  # which engines exist, what they cost, which plan tier may reach them, and the DISPLAY economics
  # (credit multiplier + equivalent turns). Everything downstream (rate_table, entitlement, the
  # editor picker, the pricing page) derives from this one table.
  #
  # PROFITABILITY INVARIANT (see docs, M14): plan allowances are denominated in DOLLARS (a compute
  # budget), never in raw tokens. A token allowance sized for the flagship (Kimi) becomes a 4-digit-%
  # loss the moment it's pointed at a frontier model. So the multipliers/turns here are DISPLAY ONLY;
  # the durable ledger meters the ACTUAL provider cost of each request against the plan's dollar budget
  # (Levelcode.budget_micros). Under that scheme the worst-case margin is identical for any model mix.
  module ModelCatalog
    module_function

    # Plan tiers, ranked. A model with `min_tier: T` is reachable by any plan of rank >= rank(T).
    TIERS = { free: 0, pro: 1, pro_plus: 2, max: 3, ultra: 4 }.freeze

    # The roster. Prices are micro-dollars per token (== $/M tokens). `status` records HOW a row's price
    # was established — a per-row property, deliberately not a point-in-time statement about the roster:
    #   :confirmed  — a verified provider list price (each row cites its source + date inline). Only
    #                 confirmed rows are selectable/billable; entitlement then gates access by min_tier.
    #   :assumption — a lineage estimate: shown as "coming soon", never billable. Staged so a model can
    #                 land before its price is quoted; flip to :confirmed once a live quote is in hand.
    #                 (The ledger meters ACTUAL response cost, so an estimate only skews the DISPLAYED
    #                 multiplier, never the charge — but keep them honest and short-lived.)
    MODELS = {
      "openai/gpt-oss-120b" => {
        label: "gpt-oss-120b", provider: "openrouter",
        input: 0.03, cached_input: 0.015, output: 0.15,
        context: 131_072, min_tier: :free, status: :confirmed
      },
      "moonshotai/kimi-k2.7-code" => {
        label: "Kimi K2.7 Code", provider: "openrouter",
        input: 0.74, cached_input: 0.15, output: 3.50,
        context: 262_144, min_tier: :pro, status: :confirmed
      },
      # Frontier rows re-verified against the OpenRouter models API on 2026-07-26 -- the earlier lineage
      # estimates were wrong (Codex even carried a non-existent slug). Ordered by COST (ascending multiplier),
      # the monotonic-multiplier invariant (spec) the picker relies on.
      "anthropic/claude-sonnet-5" => {
        label: "Sonnet 5", provider: "openrouter",
        # OpenRouter 2026-07-26: $2/M in, $10/M out, $0.20/M cached, 1M ctx.
        input: 2.00, cached_input: 0.20, output: 10.00,
        context: 1_000_000, min_tier: :pro, status: :confirmed
      },
      "openai/gpt-5.3-codex" => {
        label: "Codex 5.3", provider: "openrouter",
        # OpenRouter 2026-07-26 (openai/gpt-5.3-codex): $1.75/M in, $14/M out, $0.175/M cached, 400K ctx.
        # The old `openai/codex-5.3` slug does NOT exist on OpenRouter -- it would 404 / fall back to max rate.
        input: 1.75, cached_input: 0.175, output: 14.00,
        context: 400_000, min_tier: :pro, status: :confirmed
      },
      # K3 sits by its ~4.00x multiplier, not next to Kimi K2.7 -- the monotonic-multiplier invariant (spec).
      "moonshotai/kimi-k3" => {
        label: "Kimi K3", provider: "openrouter",
        # Confirmed vs OpenRouter (2026-07-20): $3/M in · $15/M out · $0.30/M cached read. Reached via
        # OpenRouter like every moonshotai/* slug (the native MoonshotAdapter is a disabled stub). K3 is
        # always-on reasoning with no non-thinking mode, and the reasoning trace bills at the output rate;
        # the ledger meters real usage, so that is covered. OpenRouter flags upstream capacity as limited
        # (429s) this early — fine for an opt-in Pro pick, a reason NOT to make it the default yet.
        input: 3.00, cached_input: 0.30, output: 15.00,
        context: 1_048_576, min_tier: :pro, status: :confirmed
      },
      "anthropic/claude-opus-4-8" => {
        label: "Opus 4.8", provider: "openrouter",
        # Confirmed vs OpenRouter (2026-07-07): output $25/M; input list ~$5/M (effective ~$1.56
        # after ~75% prompt-cache), cached read $0.50/M. Metering splits cached/uncached, so bills right.
        # Context corrected 200K → 1M (2026-07-24): every OpenRouter endpoint for this model — Anthropic
        # first-party, Bedrock, Azure, Google — advertises 1M/128K. The old 200K was the pre-1M default.
        input: 5.00, cached_input: 0.50, output: 25.00,
        context: 1_000_000, min_tier: :pro, status: :confirmed
      },
      # Sits immediately after Opus 4.8 because the rates are IDENTICAL ($5/$0.50/$25) — the two share
      # a multiplier, and equal neighbours keep the monotonic-multiplier invariant (spec) intact. That
      # invariant orders by COST, not recency, so the newer model does not jump the queue.
      "anthropic/claude-opus-5" => {
        label: "Opus 5", provider: "openrouter",
        # Confirmed vs the OpenRouter models API (2026-07-24): $5/M in · $25/M out · $0.50/M cached
        # read — the same sheet as Opus 4.8, so Pro's per-turn economics are unchanged; what the plan
        # gains is the newer model and a 1M window. Reached via OpenRouter like every other slug here.
        # `context` is load-bearing, and in the UNDER-reserving direction: estimate_cost_micros clamps
        # its input estimate DOWN to this number, so a too-small value makes the admission guard
        # reserve less than the request can cost and wave through turns that overrun the budget.
        input: 5.00, cached_input: 0.50, output: 25.00,
        context: 1_000_000, min_tier: :pro, status: :confirmed
      },
      "openai/gpt-5.5" => {
        label: "GPT-5.5", provider: "openrouter",
        # OpenRouter 2026-07-26: $5/M in, $30/M out, $0.50/M cached, 1.05M ctx (922K in / 128K out).
        input: 5.00, cached_input: 0.50, output: 30.00,
        context: 1_050_000, min_tier: :pro, status: :confirmed
      },
      "anthropic/claude-fable-5" => {
        label: "Fable 5", provider: "openrouter",
        # OpenRouter 2026-07-26: $10/M in, $50/M out, $1/M cached, 1M ctx. ~13.3x -> ~28 Pro turns;
        # gated to Max/Ultra so it never feels broken (rec #3).
        input: 10.00, cached_input: 1.00, output: 50.00,
        context: 1_000_000, min_tier: :max, status: :confirmed
      }
    }.freeze

    # The reference "turn" the display multipliers + turns-left are derived against: 40k input
    # (50% cached) + 5.3k output — the shape the published token allowances were sized to, so the
    # numbers reproduce the pricing table exactly. NOT used for billing (the ledger uses real cost).
    REFERENCE_TURN = { input: 40_000, output: 5_300, cache_ratio: 0.5 }.freeze

    def all = MODELS
    def ids = MODELS.keys
    def find(id) = MODELS[id.to_s]
    def exists?(id) = MODELS.key?(id.to_s)
    def label(id) = (find(id) || {})[:label] || id.to_s

    # { model_id => {input:, cached_input:, output:} } — the source of Levelcode.rate_table.
    def rate_table
      MODELS.transform_values { |m| { input: m[:input], cached_input: m[:cached_input], output: m[:output] } }
    end

    def tier_rank(tier) = TIERS[tier.to_s.to_sym] || 0

    # The most EXPENSIVE confirmed per-token rates (per field) — the conservative fallback when a
    # request's billing model id isn't in the catalog (e.g. an upstream-substituted or dated-snapshot
    # slug). Billing an unknown id at these rates means an off-catalog model can never UNDER-bill (the
    # safe money direction). Memoized; MODELS is frozen.
    def max_confirmed_rate
      @max_confirmed_rate ||= begin
        confirmed = MODELS.values.select { |m| m[:status] == :confirmed }
        {
          input:        confirmed.map { |m| m[:input] }.max,
          cached_input: confirmed.map { |m| m[:cached_input] }.max,
          output:       confirmed.map { |m| m[:output] }.max
        }
      end
    end

    # Cost (micro-$) of one REFERENCE_TURN on a model at that turn's cache ratio.
    def reference_cost_micros(id)
      m = find(id)
      return 0 unless m

      inp = REFERENCE_TURN[:input]
      out = REFERENCE_TURN[:output]
      cached = (inp * REFERENCE_TURN[:cache_ratio]).round
      billed = inp - cached
      (billed * m[:input] + cached * m[:cached_input] + out * m[:output]).round
    end

    # Credit multiplier = a model's per-turn cost relative to the flagship's, 2 dp. DERIVED from
    # prices, so it can never drift from the pricing math into a hand-entered magic number.
    def multiplier(id)
      base = reference_cost_micros(Levelcode::DEFAULT_MODEL)
      return 0.0 if base.zero?

      (reference_cost_micros(id).to_f / base).round(2)
    end

    # The model ids a plan tier is entitled to (its rank >= the model's min_tier rank), catalog order.
    def entitled(tier)
      rank = tier_rank(tier)
      MODELS.select { |_id, m| tier_rank(m[:min_tier]) <= rank }.keys
    end
  end
end
