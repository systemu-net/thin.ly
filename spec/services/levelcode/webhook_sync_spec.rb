require "rails_helper"

# rubocop:disable Metrics/BlockLength
RSpec.describe Levelcode::WebhookSync do
  let(:user) { create(:user, stripe_id: "cus_test123") }

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: "cus_test123"))
    user # materialize
    # Stub the LevelCode welcome mailer so provisioning tests neither render nor enqueue a real email;
    # the dedicated block below asserts exactly when it fires.
    @welcome_delivery = double("delivery", deliver_later: true)
    @mailer = double("mailer", welcome: @welcome_delivery, plan_changed: @welcome_delivery, canceled: @welcome_delivery)
    allow(LevelcodeBillingMailer).to receive(:with).and_return(@mailer)
  end

  # A Stripe subscription double whose single item carries the given lookup_key.
  def stripe_subscription(lookup_key:, period_start: 1_700_000_000, period_end: 1_702_678_400, status: "active")
    price = double("price", id: "price_#{lookup_key}", lookup_key: lookup_key)
    item = double("item", price: price, current_period_start: period_start, current_period_end: period_end)
    double("Stripe::Subscription", id: "sub_123", status: status, items: double("items", data: [ item ]))
  end

  def event(type, object)
    double("Stripe::Event", type: type, data: double("data", object: object))
  end

  describe "checkout.session.completed" do
    let(:session) { double("session", mode: "subscription", subscription: "sub_123", customer: "cus_test123") }

    before do
      allow(Stripe::Subscription).to receive(:retrieve).with("sub_123")
        .and_return(stripe_subscription(lookup_key: "orbits_pro"))
    end

    it "provisions a CreditWallet with the plan's caps" do
      expect {
        described_class.call(event("checkout.session.completed", session))
      }.to change { CreditWallet.where(user: user, product: "levelcode").count }.by(1)

      wallet = CreditWallet.find_by(user: user, product: "levelcode")
      plan = Levelcode.plan("orbits_pro")
      expect(wallet.plan_key).to eq("orbits_pro")
      expect(wallet.input_cap).to eq(plan[:input_cap])
      expect(wallet.output_cap).to eq(plan[:output_cap])
      expect(wallet.input_used).to eq(0)
      expect(wallet.output_used).to eq(0)
    end

    it "ignores non-subscription checkout sessions" do
      one_time = double("session", mode: "payment", subscription: nil, customer: "cus_test123")
      expect {
        described_class.call(event("checkout.session.completed", one_time))
      }.not_to change(CreditWallet, :count)
    end
  end

  describe "invoice.paid" do
    let(:invoice) do
      double("invoice",
             parent: double("parent", subscription_details: double("sd", subscription: "sub_123")),
             customer: "cus_test123")
    end

    before do
      allow(Stripe::Subscription).to receive(:retrieve).with("sub_123")
        .and_return(stripe_subscription(lookup_key: "orbits_pro"))
    end

    it "resets the used counters for the new period" do
      CreditWallet.create!(
        user: user, product: "levelcode", plan_key: "orbits_pro",
        input_cap: 1, output_cap: 1, input_used: 999, output_used: 888,
        period_start: 1.month.ago, period_end: 1.day.ago, overage_policy: "throttle"
      )

      described_class.call(event("invoice.paid", invoice))

      wallet = CreditWallet.find_by(user: user, product: "levelcode")
      expect(wallet.input_used).to eq(0)
      expect(wallet.output_used).to eq(0)
      expect(wallet.input_cap).to eq(Levelcode.plan("orbits_pro")[:input_cap])
    end
  end

  describe "Stripe API errors during a subscription retrieve" do
    let(:invoice) do
      double("invoice",
             parent: double("parent", subscription_details: double("sd", subscription: "sub_123")),
             customer: "cus_test123")
    end

    it "re-raises a TRANSIENT error (APIConnectionError) as SyncError — worth a webhook retry" do
      allow(Stripe::Subscription).to receive(:retrieve).and_raise(Stripe::APIConnectionError.new("net"))
      expect { described_class.call(event("invoice.paid", invoice)) }
        .to raise_error(Levelcode::WebhookSync::SyncError)
    end

    it "re-raises a Stripe-side 5xx (APIError) as SyncError" do
      allow(Stripe::Subscription).to receive(:retrieve).and_raise(Stripe::APIError.new("stripe is down"))
      expect { described_class.call(event("invoice.paid", invoice)) }
        .to raise_error(Levelcode::WebhookSync::SyncError)
    end

    it "SWALLOWS a PERMANENT error (InvalidRequestError) — acked, not retried" do
      allow(Stripe::Subscription).to receive(:retrieve)
        .and_raise(Stripe::InvalidRequestError.new("no such subscription", "subscription"))
      expect { described_class.call(event("invoice.paid", invoice)) }.not_to raise_error
    end
  end

  describe "customer.subscription.updated" do
    it "re-provisions caps for the new plan without zeroing usage mid-period" do
      CreditWallet.create!(
        user: user, product: "levelcode", plan_key: "orbits_pro",
        input_cap: 10, output_cap: 10, input_used: 5, output_used: 5,
        period_start: 1.day.ago, period_end: 1.month.from_now, overage_policy: "throttle"
      )

      sub = stripe_subscription(lookup_key: "orbits_pro_plus")
      allow(sub).to receive(:customer).and_return("cus_test123")

      described_class.call(event("customer.subscription.updated", sub))

      wallet = CreditWallet.find_by(user: user, product: "levelcode")
      expect(wallet.plan_key).to eq("orbits_pro_plus")
      expect(wallet.input_cap).to eq(Levelcode.plan("orbits_pro_plus")[:input_cap])
      expect(wallet.input_used).to eq(5)
    end
  end

  describe "past_due / non-active subscription" do
    it "does NOT (re)provision the paid budget — a failed renewal keeps no paying-tier credits" do
      CreditWallet.create!(
        user: user, product: "levelcode", plan_key: "orbits_pro",
        input_cap: 10, output_cap: 10, input_used: 3, output_used: 3,
        budget_micros: 5_000_000, spent_micros: 4_000_000,
        period_start: 1.day.ago, period_end: 1.month.from_now, overage_policy: "throttle"
      )
      # A past_due event for a PRICIER plan would otherwise refill the wallet to the ultra budget.
      sub = stripe_subscription(lookup_key: "orbits_ultra", status: "past_due")
      allow(sub).to receive(:customer).and_return("cus_test123")

      described_class.call(event("customer.subscription.updated", sub))

      wallet = CreditWallet.find_by(user: user, product: "levelcode")
      expect(wallet.plan_key).to eq("orbits_pro")   # unchanged — not upgraded on a delinquent sub
      expect(wallet.budget_micros).to eq(5_000_000) # NOT refilled to the ultra budget
      expect(wallet.spent_micros).to eq(4_000_000)  # spend not reset
    end
  end

  describe "customer.subscription.updated with an ADVANCING period_end" do
    it "resets spend when the billing period advances (treats it as a fresh period)" do
      old_end = Time.at(1_700_000_000).to_datetime
      CreditWallet.create!(
        user: user, product: "levelcode", plan_key: "orbits_pro",
        input_cap: 10, output_cap: 10, input_used: 7, output_used: 7,
        budget_micros: 10_000_000, spent_micros: 9_000_000,
        period_start: old_end - 1.month, period_end: old_end, overage_policy: "throttle"
      )
      # New period_end AFTER the stored one → a roll, so the prior period's spend must not carry over.
      sub = stripe_subscription(lookup_key: "orbits_pro", period_start: 1_700_000_000, period_end: 1_705_000_000)
      allow(sub).to receive(:customer).and_return("cus_test123")

      described_class.call(event("customer.subscription.updated", sub))

      wallet = CreditWallet.find_by(user: user, product: "levelcode")
      expect(wallet.spent_micros).to eq(0)
      expect(wallet.input_used).to eq(0)
    end
  end

  describe "customer.subscription.deleted" do
    it "tears the wallet down to free when a LEVELCODE subscription is canceled" do
      CreditWallet.create!(
        user: user, product: "levelcode", plan_key: "orbits_pro",
        input_cap: 10, output_cap: 10, input_used: 5, output_used: 5,
        period_start: 1.day.ago, period_end: 1.month.from_now, overage_policy: "throttle"
      )

      sub = stripe_subscription(lookup_key: "orbits_pro")
      allow(sub).to receive(:customer).and_return("cus_test123")
      described_class.call(event("customer.subscription.deleted", sub))

      wallet = CreditWallet.find_by(user: user, product: "levelcode")
      expect(wallet.plan_key).to eq("free")
      expect(wallet.input_cap).to eq(0)
      expect(wallet.input_used).to eq(0)
    end

    it "does NOT tear down the LevelCode wallet when a SHORTENER subscription is canceled (shared account)" do
      CreditWallet.create!(
        user: user, product: "levelcode", plan_key: "orbits_pro",
        input_cap: 10, output_cap: 10, input_used: 5, output_used: 5,
        period_start: 1.day.ago, period_end: 1.month.from_now, overage_policy: "throttle"
      )

      # A link-shortener price carries a non-Levelcode lookup_key.
      sub = stripe_subscription(lookup_key: "creator_monthly")
      allow(sub).to receive(:customer).and_return("cus_test123")
      described_class.call(event("customer.subscription.deleted", sub))

      wallet = CreditWallet.find_by(user: user, product: "levelcode")
      expect(wallet.plan_key).to eq("orbits_pro") # untouched — the paid LevelCode wallet survives
      expect(wallet.input_cap).to eq(10)
      expect(wallet.input_used).to eq(5)
    end
  end

  describe "non-levelcode events" do
    it "no-ops for a linkly-product subscription (unknown lookup_key)" do
      sub = stripe_subscription(lookup_key: "creator_monthly")
      allow(sub).to receive(:customer).and_return("cus_test123")

      expect {
        described_class.call(event("customer.subscription.updated", sub))
      }.not_to change(CreditWallet, :count)
    end
  end

  describe "LevelCode Cloud welcome email (fires once, on first paid purchase)" do
    let(:session) { double("session", mode: "subscription", subscription: "sub_123", customer: "cus_test123") }

    before do
      allow(Stripe::Subscription).to receive(:retrieve).with("sub_123")
        .and_return(stripe_subscription(lookup_key: "orbits_pro"))
    end

    def paid_wallet!(plan_key: "orbits_pro", period_end: 1.month.from_now)
      CreditWallet.create!(
        user: user, product: "levelcode", plan_key: plan_key,
        input_cap: 10, output_cap: 10, period_start: 1.day.ago, period_end: period_end, overage_policy: "throttle"
      )
    end

    it "queues the welcome on a brand-new wallet (checkout.session.completed)" do
      described_class.call(event("checkout.session.completed", session))

      expect(LevelcodeBillingMailer).to have_received(:with).with(hash_including(plan_key: "orbits_pro"))
      expect(@welcome_delivery).to have_received(:deliver_later)
    end

    it "queues the welcome on a free→paid upgrade (a FREE wallet already exists)" do
      CreditWallet.create!(
        user: user, product: "levelcode", plan_key: Levelcode::FREE_PLAN_KEY,
        input_cap: 0, output_cap: 0, budget_micros: 0,
        period_start: 2.days.ago, period_end: 1.day.ago, overage_policy: "throttle"
      )

      described_class.call(event("checkout.session.completed", session))

      expect(LevelcodeBillingMailer).to have_received(:with).with(hash_including(plan_key: "orbits_pro"))
    end

    it "does NOT queue a welcome on a renewal (already-paid wallet, invoice.paid)" do
      paid_wallet!(period_end: 1.day.ago)
      invoice = double("invoice",
                       parent: double("parent", subscription_details: double("sd", subscription: "sub_123")),
                       customer: "cus_test123")

      described_class.call(event("invoice.paid", invoice))

      expect(LevelcodeBillingMailer).not_to have_received(:with)
    end

    it "does NOT queue a WELCOME on a plan change (that path sends a plan-change email instead)" do
      paid_wallet!
      sub = stripe_subscription(lookup_key: "orbits_pro_plus")
      allow(sub).to receive(:customer).and_return("cus_test123")

      described_class.call(event("customer.subscription.updated", sub))

      expect(@mailer).not_to have_received(:welcome)
    end

    it "is best-effort: an email enqueue failure never escapes as SyncError, and provisioning still commits" do
      allow(LevelcodeBillingMailer).to receive(:with).and_raise(StandardError, "queue down")

      expect { described_class.call(event("checkout.session.completed", session)) }.not_to raise_error
      expect(CreditWallet.find_by(user: user, product: "levelcode").plan_key).to eq("orbits_pro")
    end
  end

  describe "LevelCode plan-change & cancellation emails" do
    def paid_wallet!(plan_key: "orbits_pro", period_end: 1.month.from_now)
      CreditWallet.create!(
        user: user, product: "levelcode", plan_key: plan_key,
        input_cap: 10, output_cap: 10, period_start: 1.day.ago, period_end: period_end, overage_policy: "throttle"
      )
    end

    it "queues an UPGRADE email on a paid→pricier change (Pro → Pro+)" do
      paid_wallet!(plan_key: "orbits_pro")
      sub = stripe_subscription(lookup_key: "orbits_pro_plus")
      allow(sub).to receive(:customer).and_return("cus_test123")

      described_class.call(event("customer.subscription.updated", sub))

      expect(LevelcodeBillingMailer).to have_received(:with)
        .with(hash_including(direction: "upgrade", plan_key: "orbits_pro_plus"))
      expect(@mailer).to have_received(:plan_changed)
      expect(@welcome_delivery).to have_received(:deliver_later)
      expect(@mailer).not_to have_received(:welcome)
    end

    it "queues a DOWNGRADE email on a paid→cheaper change (Ultra → Pro)" do
      paid_wallet!(plan_key: "orbits_ultra")
      sub = stripe_subscription(lookup_key: "orbits_pro")
      allow(sub).to receive(:customer).and_return("cus_test123")

      described_class.call(event("customer.subscription.updated", sub))

      expect(LevelcodeBillingMailer).to have_received(:with)
        .with(hash_including(direction: "downgrade", plan_key: "orbits_pro"))
      expect(@mailer).to have_received(:plan_changed)
      expect(@welcome_delivery).to have_received(:deliver_later)
      expect(@mailer).not_to have_received(:welcome)
    end

    it "does NOT queue a plan-change email on a renewal (same plan, invoice.paid)" do
      paid_wallet!(plan_key: "orbits_pro", period_end: 1.day.ago)
      allow(Stripe::Subscription).to receive(:retrieve).with("sub_123")
        .and_return(stripe_subscription(lookup_key: "orbits_pro"))
      invoice = double("invoice",
                       parent: double("parent", subscription_details: double("sd", subscription: "sub_123")),
                       customer: "cus_test123")

      described_class.call(event("invoice.paid", invoice))

      expect(@mailer).not_to have_received(:plan_changed)
    end

    it "queues a CANCELLATION email on customer.subscription.deleted (was on a paid plan) + resets to free" do
      paid_wallet!(plan_key: "orbits_pro_plus")
      deleted = stripe_subscription(lookup_key: "orbits_pro_plus")
      allow(deleted).to receive(:customer).and_return("cus_test123")

      described_class.call(event("customer.subscription.deleted", deleted))

      expect(LevelcodeBillingMailer).to have_received(:with).with(hash_including(plan_key: "orbits_pro_plus"))
      expect(@mailer).to have_received(:canceled)
      expect(@welcome_delivery).to have_received(:deliver_later)
      expect(CreditWallet.find_by(user: user, product: "levelcode").plan_key).to eq("free")
    end
  end
end
# rubocop:enable Metrics/BlockLength
