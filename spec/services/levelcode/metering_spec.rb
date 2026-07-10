# frozen_string_literal: true

require "rails_helper"

RSpec.describe Levelcode::Metering do
  # unlocked_budget_micros is a PURE function — time is passed explicitly, no Redis needed.
  let(:t0)   { Time.utc(2026, 1, 1) }
  let(:fin)  { t0 + (30 * 24 * 60 * 60) } # 30-day period → window = 10 days at N=3
  let(:full) { 10_000_000 }               # $10, the orbits_pro budget

  def wallet(budget: full, plan_key: "orbits_pro", start: t0, finish: fin, created: t0)
    instance_double(
      "CreditWallet", budget_micros: budget, plan_key: plan_key,
      period_start: start, period_end: finish, created_at: created
    )
  end

  def unlocked(wal, now) = described_class.unlocked_budget_micros(wal, now)

  describe ".unlocked_budget_micros" do
    context "with tranching DISABLED (the safe default, N=1)" do
      it "returns the full budget at any point in the period (zero behavior change on ship)" do
        expect(Levelcode::BUDGET_TRANCHES).to eq(1)
        expect(unlocked(wallet, t0)).to eq(full)
        expect(unlocked(wallet, fin)).to eq(full)
      end
    end

    context "with tranching ENABLED (N=3)" do
      before { stub_const("Levelcode::BUDGET_TRANCHES", 3) }
      let(:window) { (fin - t0) / 3 } # 10 days

      it "unlocks one tranche at the start (k=1 → budget/3)" do
        expect(unlocked(wallet, t0)).to eq(full / 3) # 3_333_333
      end

      it "unlocks two tranches after one window (k=2)" do
        expect(unlocked(wallet, t0 + window)).to eq(2 * full / 3) # 6_666_666
      end

      it "unlocks the whole budget after the last window (k=3)" do
        expect(unlocked(wallet, t0 + (2 * window))).to eq(full)
      end

      it "equals the full budget EXACTLY at period_end (rounding remainder lands in the last tranche)" do
        expect(unlocked(wallet, t0) * 3).to be < full # early steps are floored (9_999_999)
        expect(unlocked(wallet, fin)).to eq(full)     # but the whole is exact (10_000_000)
      end

      it "clamps a future / clock-skewed start to the first tranche (k=1)" do
        expect(unlocked(wallet, t0 - (5 * 24 * 60 * 60))).to eq(full / 3)
      end

      it "NEVER tranches the free tier — returns its full (small) budget from day one" do
        expect(unlocked(wallet(plan_key: "free", budget: 300_000), t0)).to eq(300_000)
      end

      it "returns 0 for a no-plan wallet (budget 0) without dividing" do
        expect(unlocked(wallet(budget: 0), t0)).to eq(0)
      end

      it "fails open to the full budget when period_start is missing (never anchors to an unrelated time)" do
        expect(unlocked(wallet(start: nil, finish: fin), t0 + window)).to eq(full) # start nil, end set → full
        expect(unlocked(wallet(start: nil, finish: nil), t0)).to eq(full)
      end

      it "fails open (never raises) for a pathological tranche count that underflows the window" do
        stub_const("Levelcode::BUDGET_TRANCHES", 10**400) # window = period / n → 0.0
        expect { unlocked(wallet, t0 + (10 * 24 * 60 * 60)) }.not_to raise_error
        expect(unlocked(wallet, t0 + (10 * 24 * 60 * 60))).to eq(full)
      end

      it "is monotonic non-decreasing and never exceeds the budget across the whole period" do
        vals = (0..30).map { |d| unlocked(wallet, t0 + (d * 24 * 60 * 60)) }
        expect(vals).to eq(vals.sort)
        expect(vals.max).to eq(full)
        expect(vals.min).to eq(full / 3)
      end
    end
  end

  describe "over_budget? (private) routes enforcement through the unlocked ceiling" do
    before { stub_const("Levelcode::BUDGET_TRANCHES", 3) }

    it "blocks in the first window once spend reaches budget/3 even though the full budget is higher" do
      w = wallet
      allow(described_class).to receive(:unlocked_budget_micros).with(w).and_return(full / 3)
      # gated at the tranche ($3.33), NOT the full budget ($10) — this is the whole point of Phase 1.
      expect(described_class.send(:over_budget?, (full / 3) - 1, w)).to be(false)
      expect(described_class.send(:over_budget?, full / 3, w)).to be(true)
    end
  end

  # The OTHER enforcement site — reserve!'s concurrency guard — must also gate at the unlocked ceiling,
  # not the full budget, or a burst of concurrent admissions could overshoot the tranche once Phase 2
  # flips tranching on. Redis is stubbed so this stays a focused unit test.
  describe "reserve! (concurrency guard) gates at the unlocked ceiling" do
    let(:spent_key) { "levelcode:used:test:spent" }
    let(:paid) { wallet } # memoized so the before-block stub and the example share ONE double

    before do
      stub_const("Levelcode::BUDGET_TRANCHES", 3)
      allow(described_class).to receive(:key).and_return(spent_key)
      allow(described_class).to receive(:unlocked_budget_micros).with(paid).and_return(full / 3) # $3.33 window
    end

    it "admits a reservation that fits within the current tranche" do
      allow(described_class).to receive(:redis).and_return(double("redis", expire: nil, incrby: 3_000_000))
      expect(described_class.reserve!(paid, 3_000_000)).to have_attributes(ok: true, amount: 3_000_000)
    end

    it "rejects + rolls back a reservation over the tranche, even though it's under the full budget" do
      fake = double("redis", expire: nil)
      allow(described_class).to receive(:redis).and_return(fake)
      allow(fake).to receive(:incrby).with(spent_key, 4_000_000).and_return(4_000_000)  # $4.0 > $3.33 tranche
      expect(fake).to receive(:incrby).with(spent_key, -4_000_000).and_return(0)         # rolled back
      expect(described_class.reserve!(paid, 4_000_000).ok).to be(false)
    end
  end
end
