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

    # The roster. Prices are micro-dollars per token (== $/M tokens). `status`:
    #   :confirmed  — a verified provider list price.
    #   :assumption — a lineage-based estimate. It MUST be replaced with a live quote before the model
    #                 is billed on. (Because the ledger meters ACTUAL response cost, an assumed price
    #                 only skews the DISPLAYED multiplier, never the charge — but keep them honest.)
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
      "openai/codex-5.3" => {
        label: "Codex 5.3", provider: "openrouter",
        input: 1.25, cached_input: 0.125, output: 10.00,
        context: 400_000, min_tier: :pro, status: :assumption
      },
      "openai/gpt-5.5" => {
        label: "GPT-5.5", provider: "openrouter",
        input: 1.50, cached_input: 0.15, output: 12.00,
        context: 400_000, min_tier: :pro, status: :assumption
      },
      "anthropic/claude-sonnet-5" => {
        label: "Sonnet 5", provider: "openrouter",
        input: 3.00, cached_input: 0.30, output: 15.00,
        context: 200_000, min_tier: :pro, status: :assumption
      },
      "anthropic/claude-opus-4-8" => {
        label: "Opus 4.8", provider: "openrouter",
        # Confirmed vs OpenRouter (2026-07-07): output $25/M; input list ~$5/M (effective ~$1.56
        # after ~75% prompt-cache), cached read $0.50/M. Metering splits cached/uncached, so bills right.
        input: 5.00, cached_input: 0.50, output: 25.00,
        context: 200_000, min_tier: :pro, status: :confirmed
      },
      "anthropic/claude-fable-5" => {
        label: "Fable 5", provider: "openrouter",
        input: 10.00, cached_input: 1.00, output: 50.00,
        # 13.35× → only ~28 Pro turns; gated to Max/Ultra so it never feels broken (rec #3).
        context: 200_000, min_tier: :max, status: :assumption
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
