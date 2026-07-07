require "rails_helper"

# Proves the credit economics are DERIVED from prices and reproduce the M14 analysis, and that the
# design invariants hold (entitlement tiers, monotonic multipliers, dollar-denominated budgets).
RSpec.describe Levelcode::ModelCatalog do
  describe "roster integrity" do
    it "marks only the verified engines as confirmed; frontier rows are assumptions" do
      expect(described_class.find("openai/gpt-oss-120b")[:status]).to eq(:confirmed)
      expect(described_class.find("moonshotai/kimi-k2.7-code")[:status]).to eq(:confirmed)
      assumed = described_class.all.select { |_id, m| m[:status] == :assumption }.keys
      expect(assumed).to include("anthropic/claude-opus-4-8", "anthropic/claude-fable-5", "openai/gpt-5.5")
    end

    it "rate_table exposes every roster model's per-token rates (feeds Levelcode.cost_micros)" do
      expect(described_class.rate_table["moonshotai/kimi-k2.7-code"]).to eq(input: 0.74, cached_input: 0.15, output: 3.50)
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
        "openai/gpt-5.5" => 2.66, "anthropic/claude-sonnet-5" => 4.00, "anthropic/claude-opus-4-8" => 6.67,
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
      expect(pro).to include("moonshotai/kimi-k2.7-code", "anthropic/claude-opus-4-8", "openai/gpt-5.5")
      expect(pro).not_to include("anthropic/claude-fable-5")
    end

    it "Max/Ultra reach the full roster incl. Fable" do
      expect(described_class.entitled(:max)).to include("anthropic/claude-fable-5")
      expect(described_class.entitled(:ultra)).to match_array(described_class.ids)
    end
  end
end

RSpec.describe "Levelcode credit economics (M14)" do
  describe ".budget_micros — the DOLLAR compute budget (flagship worst-case)" do
    it "matches the analysis budgets (~$14.43 / $33.05 / $51.67 / $88.91), within cents" do
      { "orbits_pro" => 14_430_000, "orbits_pro_plus" => 33_050_000,
        "orbits_max" => 51_670_000, "orbits_ultra" => 88_910_000 }.each do |key, expected|
        expect(Levelcode.budget_micros(key)).to be_within(60_000).of(expected)
      end
    end

    it "increases with tier; free/unknown plans have no paid budget" do
      expect(Levelcode.budget_micros("orbits_pro")).to be < Levelcode.budget_micros("orbits_ultra")
      expect(Levelcode.budget_micros("free")).to eq(0)
    end
  end

  describe ".turns_for — equivalent turns a budget buys on a model" do
    it "reproduces the analysis turn counts (within rounding)" do
      expect(Levelcode.turns_for("orbits_pro", "moonshotai/kimi-k2.7-code")).to be_within(2).of(375)
      expect(Levelcode.turns_for("orbits_pro", "anthropic/claude-opus-4-8")).to be_within(2).of(56)
      expect(Levelcode.turns_for("orbits_pro", "anthropic/claude-fable-5")).to be_within(2).of(28)
      expect(Levelcode.turns_for("orbits_pro", "openai/gpt-oss-120b")).to be > 7_000
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
