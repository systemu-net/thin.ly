require "rails_helper"

# rubocop:disable Metrics/BlockLength
RSpec.describe Levelcode::PlanChange do
  let(:user) { create(:user, stripe_id: "cus_test123") }

  # Period the customer has ALREADY PAID FOR: started yesterday, ends in 20 days. A downgrade must not
  # touch their entitlement until period_end.
  let(:period_start) { 1.day.ago.to_i }
  let(:period_end)   { 20.days.from_now.to_i }

  let(:ultra_price) { double("Stripe::Price", id: "price_ultra", unit_amount: 10_000, lookup_key: "orbits_ultra") }
  let(:pro_price)   { double("Stripe::Price", id: "price_pro",   unit_amount: 2_000,  lookup_key: "orbits_pro") }

  # An active subscription currently sitting on `price`, with no schedule attached.
  def stripe_sub(price, schedule: nil)
    item = double("item", id: "si_1", price: price,
                          current_period_start: period_start, current_period_end: period_end)
    double("Stripe::Subscription", id: "sub_x", status: "active",
                                   schedule: schedule, items: double("items", data: [ item ]))
  end

  def schedule_double(id: "sub_sched_1")
    phase = double("phase", start_date: period_start, end_date: period_end)
    double("Stripe::SubscriptionSchedule", id: id, phases: [ phase ])
  end

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: "cus_test123"))
    user # materialize
    @delivery = double("delivery", deliver_later: true)
    @mailer = double("mailer", plan_changed: @delivery)
    allow(LevelcodeBillingMailer).to receive(:with).and_return(@mailer)
  end

  def call(new_price)
    described_class.call(user: user, subscription_id: "sub_x", new_price: new_price)
  end

  describe "upgrade (Pro → Ultra)" do
    before do
      allow(Stripe::Subscription).to receive(:retrieve).with("sub_x").and_return(stripe_sub(pro_price))
      allow(Stripe::Subscription).to receive(:update).and_return(double("updated"))
    end

    it "swaps the price IMMEDIATELY and prorates the difference" do
      expect(Stripe::Subscription).to receive(:update).with(
        "sub_x",
        hash_including(
          items: [ { id: "si_1", price: "price_ultra" } ],
          proration_behavior: "create_prorations"
        )
      ).and_return(double("updated"))

      expect(call(ultra_price).change_type).to eq("upgraded")
    end

    it "never opens a subscription schedule (upgrades take effect now)" do
      expect(Stripe::SubscriptionSchedule).not_to receive(:create)
      expect(Stripe::SubscriptionSchedule).not_to receive(:update)
      expect(Stripe::SubscriptionSchedule).not_to receive(:release)
      call(ultra_price)
    end

    # Upgrade AFTER a scheduled downgrade: the pending schedule must be detached first, or Stripe
    # rejects the direct update / the schedule flips the price back down at the boundary anyway.
    it "releases a pending downgrade schedule BEFORE the immediate swap (never cancels it)" do
      allow(Stripe::Subscription).to receive(:retrieve).with("sub_x")
        .and_return(stripe_sub(pro_price, schedule: "sub_sched_pending"))

      expect(Stripe::SubscriptionSchedule).to receive(:release).with("sub_sched_pending").ordered
      expect(Stripe::Subscription).to receive(:update)
        .with("sub_x", hash_including(items: [ { id: "si_1", price: "price_ultra" } ])).ordered
        .and_return(double("updated"))

      expect(call(ultra_price).change_type).to eq("upgraded")
    end

    it "does NOT email — the webhook announces the upgrade when it observes the flip" do
      call(ultra_price)
      expect(LevelcodeBillingMailer).not_to have_received(:with)
    end
  end

  describe "downgrade (Ultra → Pro)" do
    let(:schedule) { schedule_double }

    before do
      allow(Stripe::Subscription).to receive(:retrieve).with("sub_x").and_return(stripe_sub(ultra_price))
      allow(Stripe::SubscriptionSchedule).to receive(:create).and_return(schedule)
      allow(Stripe::SubscriptionSchedule).to receive(:update).and_return(schedule)
    end

    # THE FIX. An immediate item swap (even with proration_behavior "none") changes the price on the Stripe
    # object at once, so customer.subscription.updated re-provisions the wallet DOWN mid-period and the
    # customer loses the tier they already paid for.
    it "NEVER swaps the subscription item immediately — that is what dropped the entitlement mid-period" do
      expect(Stripe::Subscription).not_to receive(:update)
      expect(call(pro_price).change_type).to eq("downgraded")
    end

    it "schedules the switch at the period boundary: current price until period_end, then the new one" do
      expect(Stripe::SubscriptionSchedule).to receive(:create).with(from_subscription: "sub_x").and_return(schedule)
      expect(Stripe::SubscriptionSchedule).to receive(:update).with(
        "sub_sched_1",
        hash_including(
          end_behavior: "release", # never "cancel" — that would END the subscription at the boundary
          phases: [
            {
              items: [ { price: "price_ultra", quantity: 1 } ], # keeps the HIGHER tier they paid for
              start_date: period_start,
              end_date: period_end
            },
            { items: [ { price: "price_pro", quantity: 1 } ] }  # takes over at period_end, open-ended
          ]
        )
      ).and_return(schedule)

      call(pro_price)
    end

    it "announces the scheduled downgrade now, dated at the boundary" do
      call(pro_price)

      expect(LevelcodeBillingMailer).to have_received(:with).with(
        hash_including(
          direction: "downgrade",
          plan_key: "orbits_pro",
          from_plan: Levelcode.plan("orbits_ultra"),
          plan: Levelcode.plan("orbits_pro"),
          period_end: Time.at(period_end).to_datetime
        )
      )
      expect(@delivery).to have_received(:deliver_later)
    end

    it "reuses an existing schedule rather than creating a second one (Stripe rejects two)" do
      existing = schedule_double(id: "sub_sched_existing")
      allow(Stripe::Subscription).to receive(:retrieve).with("sub_x")
        .and_return(stripe_sub(ultra_price, schedule: "sub_sched_existing"))
      allow(Stripe::SubscriptionSchedule).to receive(:retrieve).with("sub_sched_existing").and_return(existing)

      expect(Stripe::SubscriptionSchedule).not_to receive(:create)
      expect(Stripe::SubscriptionSchedule).to receive(:update).with("sub_sched_existing", anything).and_return(existing)

      call(pro_price)
    end

    # A subscriber who already went through one scheduled downgrade has a schedule whose ACTIVE phase is
    # our open-ended final phase (no end_date). The next downgrade must fall back to the item's
    # current_period_end — never Time.at(nil), never an end_date-less first phase.
    it "handles a reused schedule whose active phase is open-ended: the item's period end is the boundary" do
      open_phase = double("phase", start_date: period_start, end_date: nil)
      existing = double("Stripe::SubscriptionSchedule", id: "sub_sched_existing", phases: [ open_phase ])
      allow(Stripe::Subscription).to receive(:retrieve).with("sub_x")
        .and_return(stripe_sub(ultra_price, schedule: "sub_sched_existing"))
      allow(Stripe::SubscriptionSchedule).to receive(:retrieve).with("sub_sched_existing").and_return(existing)

      expect(Stripe::SubscriptionSchedule).to receive(:update).with(
        "sub_sched_existing",
        hash_including(
          phases: [
            {
              items: [ { price: "price_ultra", quantity: 1 } ],
              start_date: period_start,
              end_date: period_end # from the item — the phase has none
            },
            { items: [ { price: "price_pro", quantity: 1 } ] }
          ]
        )
      ).and_return(existing)

      expect(call(pro_price).change_type).to eq("downgraded")
      expect(LevelcodeBillingMailer).to have_received(:with)
        .with(hash_including(period_end: Time.at(period_end).to_datetime))
    end

    it "is best-effort about the email: an enqueue failure never fails the plan change" do
      allow(LevelcodeBillingMailer).to receive(:with).and_raise(StandardError, "queue down")
      expect { expect(call(pro_price).change_type).to eq("downgraded") }.not_to raise_error
    end
  end

  describe "equal-priced move (no real increase)" do
    it "is treated as a downgrade — scheduled, never an immediate prorated charge" do
      same_priced = double("Stripe::Price", id: "price_other", unit_amount: 10_000, lookup_key: "orbits_ultra")
      allow(Stripe::Subscription).to receive(:retrieve).with("sub_x").and_return(stripe_sub(ultra_price))
      allow(Stripe::SubscriptionSchedule).to receive(:create).and_return(schedule_double)
      allow(Stripe::SubscriptionSchedule).to receive(:update).and_return(schedule_double)

      expect(Stripe::Subscription).not_to receive(:update)
      expect(call(same_priced).change_type).to eq("downgraded")
    end
  end

  describe "guards" do
    it "raises SamePlanError when the price is the one already on the subscription" do
      allow(Stripe::Subscription).to receive(:retrieve).with("sub_x").and_return(stripe_sub(pro_price))
      expect { call(pro_price) }.to raise_error(described_class::SamePlanError)
    end

    it "raises a Stripe error when the subscription has no price item to change" do
      empty = double("Stripe::Subscription", id: "sub_x", status: "active",
                                             schedule: nil, items: double("items", data: []))
      allow(Stripe::Subscription).to receive(:retrieve).with("sub_x").and_return(empty)
      expect { call(pro_price) }.to raise_error(Stripe::StripeError)
    end
  end
end
# rubocop:enable Metrics/BlockLength
