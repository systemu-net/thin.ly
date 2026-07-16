require "rails_helper"

# rubocop:disable Metrics/BlockLength
RSpec.describe "Api::Levelcode::V1::Checkouts", type: :request do
  let(:checkout_url) { "/api/levelcode/v1/checkouts" }

  let(:stripe_customer_id) { "cus_test123" }
  let(:user) { create(:user, stripe_id: stripe_customer_id) }
  let(:subscription) { user.subscriptions.find_by(product: "levelcode") || user.subscriptions.first! }

  let(:pro_price_id)      { "price_orbits_pro" }
  let(:pro_plus_price_id) { "price_orbits_pro_plus" }

  let(:pro_price) do
    double("Stripe::Price", id: pro_price_id, unit_amount: 2000, lookup_key: "orbits_pro")
  end

  let(:pro_plus_price) do
    double("Stripe::Price", id: pro_plus_price_id, unit_amount: 4000, lookup_key: "orbits_pro_plus")
  end

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: stripe_customer_id))
    # Auth (BaseController#authenticate_levelcode!) is owned by the auth slice;
    # stub it here so this slice's specs stay isolated.
    allow_any_instance_of(Api::Levelcode::V1::BaseController).to receive(:authenticate_levelcode!).and_return(true)
    allow_any_instance_of(Api::Levelcode::V1::BaseController).to receive(:current_user).and_return(user)
  end

  # ─── Helpers ──────────────────────────────────────────────────────────────

  def stub_price_list(price)
    allow(Stripe::Price).to receive(:list).and_return(double("price_list", data: [ price ]))
  end

  def stub_price_list_empty
    allow(Stripe::Price).to receive(:list).and_return(double("price_list", data: []))
  end

  # An existing subscription sitting on `price`, mid-period (paid through 20 days out).
  def stripe_sub_on(price)
    item = double("item", id: "si_item123", price: price,
                          current_period_start: 1.day.ago.to_i, current_period_end: 20.days.from_now.to_i)
    double("Stripe::Subscription", id: "sub_existing", status: "active", schedule: nil,
                                   items: double("items", data: [ item ]))
  end

  def stub_schedule
    phase = double("phase", start_date: 1.day.ago.to_i, end_date: 20.days.from_now.to_i)
    sched = double("sched", id: "sub_sched_1", phases: [ phase ])
    allow(Stripe::SubscriptionSchedule).to receive(:create).and_return(sched)
    allow(Stripe::SubscriptionSchedule).to receive(:update).and_return(sched)
    sched
  end

  # ─── Tests ────────────────────────────────────────────────────────────────

  describe "POST /api/levelcode/v1/checkouts" do
    context "when the lookup key resolves no price" do
      before { stub_price_list_empty }

      it "returns 404 with the SPEC error shape" do
        post checkout_url, params: { lookup_key: "nope" }
        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body.dig("error", "code")).to eq("plan_not_found")
      end
    end

    # ── First-time purchase ──────────────────────────────────────────────────
    context "when the user has no active levelcode subscription" do
      let(:checkout_session) { double("Stripe::Checkout::Session", url: "https://checkout.stripe.com/session123") }

      before do
        stub_price_list(pro_price)
        allow(user).to receive(:subscriptions).and_return(
          double("subs", find_by: nil)
        )
        allow(Stripe::Checkout::Session).to receive(:create).and_return(checkout_session)
      end

      it "creates a checkout session and returns the URL" do
        post checkout_url, params: { lookup_key: "orbits_pro" }
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["url"]).to eq("https://checkout.stripe.com/session123")
      end

      it "points success/cancel at SITE_ORIGIN/account" do
        expect(Stripe::Checkout::Session).to receive(:create).with(
          hash_including(
            customer: stripe_customer_id,
            mode: "subscription",
            client_reference_id: user.id,
            success_url: a_string_matching(%r{/account\?checkout=success}),
            cancel_url: a_string_matching(%r{/account\?checkout=cancel})
          )
        ).and_return(checkout_session)

        post checkout_url, params: { lookup_key: "orbits_pro" }
      end
    end

    # ── Upgrade ──────────────────────────────────────────────────────────────
    context "when the user upgrades to a pricier plan" do
      let(:existing_sub) do
        double("Subscription", subscription_id: "sub_existing", status: "active")
      end
      let(:stripe_sub) do
        current_price = double("current_price", id: pro_price_id, unit_amount: 2000)
        item = double("item", price: current_price, id: "si_item123")
        double("Stripe::Subscription", id: "sub_existing", items: double("items", data: [ item ]), status: "active")
      end

      before do
        stub_price_list(pro_plus_price)
        allow(user).to receive(:subscriptions).and_return(double("subs", find_by: existing_sub))
        allow(Stripe::Subscription).to receive(:retrieve).with("sub_existing").and_return(stripe_sub)
        allow(Stripe::Subscription).to receive(:update).and_return(double("updated"))
      end

      it "prorates immediately and reports an upgrade" do
        expect(Stripe::Subscription).to receive(:update).with(
          "sub_existing",
          hash_including(proration_behavior: "create_prorations", items: [ hash_including(price: pro_plus_price_id) ])
        ).and_return(double("updated"))

        post checkout_url, params: { lookup_key: "orbits_pro_plus" }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["change_type"]).to eq("upgraded")
      end
    end

    # ── Downgrade ────────────────────────────────────────────────────────────
    context "when the user downgrades to a cheaper plan" do
      let(:existing_sub) { double("Subscription", subscription_id: "sub_existing", status: "active") }
      let(:ultra_price)  { double("Stripe::Price", id: "price_orbits_ultra", unit_amount: 10_000, lookup_key: "orbits_ultra") }

      before do
        stub_price_list(pro_price) # moving DOWN to Pro
        allow(user).to receive(:subscriptions).and_return(double("subs", find_by: existing_sub))
        allow(Stripe::Subscription).to receive(:retrieve).with("sub_existing").and_return(stripe_sub_on(ultra_price))
        stub_schedule
        allow(LevelcodeBillingMailer).to receive(:with)
          .and_return(double("mailer", plan_changed: double("delivery", deliver_later: true)))
      end

      # The bug this fixes: an immediate item swap (even with proration_behavior "none") lowers the price on
      # the Stripe object at once, so the wallet is re-provisioned DOWN mid-period and the customer loses the
      # Ultra allowance they already paid for.
      it "does NOT swap the subscription item immediately" do
        expect(Stripe::Subscription).not_to receive(:update)

        post checkout_url, params: { lookup_key: "orbits_pro" }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["change_type"]).to eq("downgraded")
      end

      it "schedules the switch for the period boundary, keeping the higher tier until then" do
        expect(Stripe::SubscriptionSchedule).to receive(:create).with(from_subscription: "sub_existing")
          .and_return(double("sched", id: "sub_sched_1",
                                      phases: [ double("phase", start_date: 1.day.ago.to_i, end_date: 20.days.from_now.to_i) ]))
        expect(Stripe::SubscriptionSchedule).to receive(:update).with(
          "sub_sched_1",
          hash_including(
            end_behavior: "release",
            phases: [ hash_including(items: [ { price: "price_orbits_ultra", quantity: 1 } ]),
                      hash_including(items: [ { price: pro_price_id, quantity: 1 } ]) ]
          )
        ).and_return(double("sched"))

        post checkout_url, params: { lookup_key: "orbits_pro" }
        expect(response).to have_http_status(:ok)
      end

      it "tells the customer they keep their current plan until the boundary" do
        post checkout_url, params: { lookup_key: "orbits_pro" }
        expect(response.parsed_body["message"]).to include("keep your current plan")
      end
    end

    # ── Same-plan blocked ────────────────────────────────────────────────────
    context "when the user re-buys the same plan" do
      let(:existing_sub) do
        double("Subscription", subscription_id: "sub_existing", status: "active")
      end
      let(:stripe_sub) do
        current_price = double("current_price", id: pro_price_id, unit_amount: 2000)
        item = double("item", price: current_price, id: "si_item123")
        double("Stripe::Subscription", id: "sub_existing", items: double("items", data: [ item ]), status: "active")
      end

      before do
        stub_price_list(pro_price)
        allow(user).to receive(:subscriptions).and_return(double("subs", find_by: existing_sub))
        allow(Stripe::Subscription).to receive(:retrieve).with("sub_existing").and_return(stripe_sub)
      end

      it "returns 422" do
        post checkout_url, params: { lookup_key: "orbits_pro" }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body.dig("error", "code")).to eq("already_subscribed")
      end
    end

    # ── Stripe error ─────────────────────────────────────────────────────────
    context "when Stripe raises" do
      before do
        stub_price_list(pro_price)
        allow(user).to receive(:subscriptions).and_return(double("subs", find_by: nil))
        allow(Stripe::Checkout::Session).to receive(:create)
          .and_raise(Stripe::InvalidRequestError.new("Invalid price", "price"))
      end

      it "returns 400 with the error message" do
        post checkout_url, params: { lookup_key: "orbits_pro" }
        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body.dig("error", "message")).to include("Invalid price")
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
