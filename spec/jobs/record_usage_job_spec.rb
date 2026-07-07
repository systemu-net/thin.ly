require "rails_helper"

RSpec.describe RecordUsageJob, type: :job do
  let(:user) { create(:user) }

  # The enqueue side (AiController#meter!) passes `wallet.period_end.to_i`, which TRUNCATES to whole
  # seconds. The job must match the wallet on the SAME truncated epoch — even when period_end carries
  # sub-second precision — or the durable counters silently never bump.
  def wallet_with(period_end:, **attrs)
    CreditWallet.create!(
      { user: user, product: Levelcode::PRODUCT, plan_key: "orbits_pro",
        input_cap: 15_000_000, output_cap: 2_000_000,
        budget_micros: 14_427_125, spent_micros: 0, input_used: 0, output_used: 0,
        period_start: period_end - 1.month, period_end: period_end,
        overage_policy: "throttle" }.merge(attrs)
    )
  end

  it "bumps the durable per-period counters on the first (unique) ledger insert" do
    pe = Time.zone.local(2026, 8, 7, 6, 32, 37)
    wallet = wallet_with(period_end: pe)

    described_class.new.perform(user.id, "req-1", "anthropic/claude-4.8-opus", "openrouter",
                                20_000, 800, 0, 18_068, pe.to_i)

    wallet.reload
    expect(wallet.spent_micros).to eq(18_068)
    expect(wallet.input_used).to eq(20_000)
    expect(wallet.output_used).to eq(800)
    expect(UsageEvent.where(request_id: "req-1").count).to eq(1)
  end

  # The regression: period_end stored with ≥ .5µs. Ruby to_i FLOORS (→ ...37); a bare
  # EXTRACT(EPOCH)::bigint ROUNDS UP (→ ...38). The two must still match, or spend freezes at 0.
  it "still bumps the counter when period_end has a fractional second ≥ .5 (epoch-rounding bug)" do
    pe = Time.zone.local(2026, 8, 7, 6, 32, 37) + 0.75 # rounds UP under ::bigint, floors under to_i
    wallet = wallet_with(period_end: pe)
    expect(pe.to_i).to eq(pe.to_i) # the enqueued arg is the TRUNCATED epoch (…37, not …38)

    described_class.new.perform(user.id, "req-frac", "anthropic/claude-4.8-opus", "openrouter",
                                5_000, 100, 0, 6_868, pe.to_i)

    expect(wallet.reload.spent_micros).to eq(6_868)
  end

  it "does NOT double-bump on a duplicate (same request_id) enqueue" do
    pe = Time.zone.local(2026, 8, 7, 6, 32, 37) + 0.75
    wallet = wallet_with(period_end: pe)

    2.times { described_class.new.perform(user.id, "req-dup", "m", "openrouter", 1_000, 10, 0, 500, pe.to_i) }

    expect(wallet.reload.spent_micros).to eq(500) # only the first insert bumps
    expect(UsageEvent.where(request_id: "req-dup").count).to eq(1)
  end

  it "no-ops the counter bump when the job lands after the period has rolled" do
    pe = Time.zone.local(2026, 8, 7, 6, 32, 37)
    wallet = wallet_with(period_end: pe)

    # A stale job carrying the PREVIOUS period's epoch must not corrupt the current period.
    described_class.new.perform(user.id, "req-stale", "m", "openrouter", 1_000, 10, 0, 500, (pe - 1.month).to_i)

    expect(wallet.reload.spent_micros).to eq(0)
    expect(UsageEvent.where(request_id: "req-stale").count).to eq(1) # ledger row still written
  end
end
