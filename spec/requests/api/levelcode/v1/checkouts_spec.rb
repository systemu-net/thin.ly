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
