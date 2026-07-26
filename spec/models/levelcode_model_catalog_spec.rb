require "rails_helper"

# Proves the credit economics are DERIVED from prices and reproduce the M14 analysis, and that the
# design invariants hold (entitlement tiers, monotonic multipliers, dollar-denominated budgets).
RSpec.describe Levelcode::ModelCatalog do
  describe "roster integrity" do
    it "carries a confirmed price on every roster engine — the frontier rows are enabled now" do
      %w[openai/gpt-oss-120b moonshotai/kimi-k2.7-code anthropic/claude-opus-4-8 moonshotai/kimi-k3
         anthropic/claude-opus-5 openai/codex-5.3 openai/gpt-5.5 anthropic/claude-sonnet-5
         anthropic/claude-fable-5].each do |id|
        expect(described_class.find(id)[:status]).to eq(:confirmed), id
      end
      # Nothing left staged — the "coming soon" set is empty.
      assumed = described_class.all.select { |_id, m| m[:status] == :assumption }.keys
      expect(assumed).to be_empty
    end

    # `context` is not decoration — estimate_cost_micros clamps its input estimate DOWN to it, so a
    # stale (too small) window makes the admission guard under-reserve. Both Opus rows are 1M: every
    # OpenRouter endpoint for them (Anthropic first-party, Bedrock, Azure, Google) advertises 1M/128K.
    it "carries each model's real context window" do
      expect(described_class.find("anthropic/claude-opus-4-8")[:context]).to eq(1_000_000)
      expect(described_class.find("anthropic/claude-opus-5")[:context]).to eq(1_000_000)
      expect(described_class.find("moonshotai/kimi-k3")[:context]).to eq(1_048_576)
      expect(described_class.find("openai/gpt-oss-120b")[:context]).to eq(131_072)
      # No row may go without one: a nil/0 window disables the clamp entirely.
      expect(described_class.all.values.map { |m| m[:context] }).to all(be_positive)
    end

    it "rate_table exposes every roster model's per-token rates (feeds Levelcode.cost_micros)" do
      expect(described_class.rate_table["moonshotai/kimi-k2.7-code"]).to eq(input: 0.74, cached_input: 0.15, output: 3.50)
      expect(described_class.rate_table["moonshotai/kimi-k3"]).to eq(input: 3.00, cached_input: 0.30, output: 15.00)
      expect(described_class.rate_table.keys).to match_array(described_class.ids)
    end
  end

  describe "credit multipliers (derived, DISPLAY only)" do
    it "is exactly the per-turn cost ratio to the flagship — never a hand-entered number" do
      base = described_class.reference_cost_micros(Levelcode::DEFAULT_MODEL)
      described_class.ids.each do |id|
        expect(described_class.multiplier(id)).to eq((described_class.reference_cost_micros(id).to_f / base).round(2))
      end
    end

    it "reproduces the analysis multipliers (within rounding)" do
      {
        "openai/gpt-oss-120b" => 0.05, "moonshotai/kimi-k2.7-code" => 1.00, "openai/codex-5.3" => 2.22,
        "openai/gpt-5.5" => 2.66, "anthropic/claude-sonnet-5" => 4.00, "moonshotai/kimi-k3" => 4.00,
        # Opus 5 TIES Opus 4.8 — identical rates ⇒ identical multiplier. That tie is exactly what lets
        # it sit beside 4.8 without disturbing the monotonic ordering asserted below.
        "anthropic/claude-opus-4-8" => 6.67, "anthropic/claude-opus-5" => 6.67,
        "anthropic/claude-fable-5" => 13.35
      }.each { |id, mult| expect(described_class.multiplier(id)).to be_within(0.02).of(mult) }
    end

    it "increases monotonically with price (pricier model ⇒ higher multiplier)" do
      mults = described_class.ids.map { |id| described_class.multiplier(id) }
      expect(mults).to eq(mults.sort)
      expect(described_class.multiplier(Levelcode::FREE_MODEL)).to be < described_class.multiplier(Levelcode::DEFAULT_MODEL)
    end
  end

  describe "entitlement tiers" do
    it "free reaches ONLY the open-weights engine" do
      expect(described_class.entitled(:free)).to eq([ "openai/gpt-oss-120b" ])
    end

    it "pro reaches the roster EXCEPT Fable (gated to Max/Ultra by UX, rec #3)" do
      pro = described_class.entitled(:pro)
      expect(pro).to include("moonshotai/kimi-k2.7-code", "anthropic/claude-opus-4-8", "anthropic/claude-opus-5", "openai/gpt-5.5")
      expect(pro).not_to include("anthropic/claude-fable-5")
    end

    it "Max/Ultra reach the full roster incl. Fable" do
      expect(described_class.entitled(:max)).to include("anthropic/claude-fable-5")
      expect(described_class.entitled(:ultra)).to match_array(described_class.ids)
    end
  end
end

RSpec.describe "Levelcode credit economics (M14)" do
  describe ".budget_micros — the DOLLAR compute budget (revenue × CREDIT_COGS_RATIO)" do
    it "is a fixed 50% of plan revenue ($10 / $20 / $30 / $50 of credits)" do
      { "orbits_pro" => 10_000_000, "orbits_pro_plus" => 20_000_000,
        "orbits_max" => 30_000_000, "orbits_ultra" => 50_000_000 }.each do |key, expected|
        expect(Levelcode.budget_micros(key)).to eq(expected)
      end
    end

    it "increases with tier; free/unknown plans have no paid budget" do
      expect(Levelcode.budget_micros("orbits_pro")).to be < Levelcode.budget_micros("orbits_ultra")
      expect(Levelcode.budget_micros("free")).to eq(0)
    end
  end

  describe ".retail_micros — the dashboard denomination (what the customer PAID)" do
    it "scales the cost budget back up to the plan PRICE (cost ÷ margin)" do
      # budget_micros == price × 0.50, so retail(budget) == the full price the user paid.
      { "orbits_pro" => 20_000_000, "orbits_pro_plus" => 40_000_000,
        "orbits_max" => 60_000_000, "orbits_ultra" => 100_000_000 }.each do |key, price_micros|
        expect(Levelcode.retail_micros(Levelcode.budget_micros(key), key)).to eq(price_micros)
      end
    end

    it "scales spend by the same factor (preserving the spent/budget ratio, so % and turns-left hold)" do
      cost = Levelcode.budget_micros("orbits_pro_plus")            # $20 cost
      expect(Levelcode.retail_micros(cost / 2, "orbits_pro_plus")).to eq(20_000_000) # half the cost → half of $40
    end

    it "leaves the free tier (no price) untouched" do
      expect(Levelcode.retail_micros(300_000, "free")).to eq(300_000)
      expect(Levelcode.retail_micros(300_000, nil)).to eq(300_000)
    end
  end

  describe ".turns_for — equivalent turns a budget buys on a model" do
    it "reproduces the turn counts for the $10 Pro budget (50% of revenue)" do
      expect(Levelcode.turns_for("orbits_pro", "moonshotai/kimi-k2.7-code")).to be_within(2).of(260)
      expect(Levelcode.turns_for("orbits_pro", "anthropic/claude-opus-4-8")).to be_within(2).of(39)
      expect(Levelcode.turns_for("orbits_pro", "anthropic/claude-fable-5")).to be_within(2).of(19)
      expect(Levelcode.turns_for("orbits_pro", "openai/gpt-oss-120b")).to be > 4_000
    end

    it "buys far more turns on a cheaper model for the same budget" do
      gpt = Levelcode.turns_for("orbits_max", "openai/gpt-oss-120b")
      opus = Levelcode.turns_for("orbits_max", "anthropic/claude-opus-4-8")
      expect(gpt).to be > opus * 100
    end
  end

  describe ".entitled_models / .plan_tier" do
    it "maps plan keys to tiers and gates Fable to Max/Ultra" do
      expect(Levelcode.plan_tier("orbits_pro")).to eq(:pro)
      expect(Levelcode.entitled_models("orbits_pro")).not_to include("anthropic/claude-fable-5")
      expect(Levelcode.entitled_models("orbits_ultra")).to include("anthropic/claude-fable-5")
      expect(Levelcode.entitled_models("free")).to eq([ "openai/gpt-oss-120b" ])
    end
  end
end
