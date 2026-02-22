require "rails_helper"

# rubocop:disable Metrics/BlockLength
RSpec.describe "Api::V1::Checkouts", type: :request do
  CHECKOUT_URL = "/api/v1/checkouts"

  let(:stripe_customer_id) { "cus_test123" }
  let(:user) { create(:user, stripe_id: stripe_customer_id) }
  let(:subscription) { user.subscriptions.first! }
  let(:plan) { subscription.plan }

  let(:creator_price_id)  { "price_creator_monthly" }
  let(:business_price_id) { "price_business_monthly" }

  let(:creator_price) do
    double("Stripe::Price",
           id: creator_price_id,
           unit_amount: 900,
           lookup_key: "creator_monthly")
  end

  let(:business_price) do
    double("Stripe::Price",
           id: business_price_id,
           unit_amount: 2900,
           lookup_key: "business_monthly")
  end

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: stripe_customer_id))
  end

  # ─── Helpers ──────────────────────────────────────────────────────────────

  def stub_price_list(price)
    allow(Stripe::Price).to receive(:list).and_return(
      double("price_list", data: [ price ])
    )
  end

  def stub_price_list_empty
    allow(Stripe::Price).to receive(:list).and_return(
      double("price_list", data: [])
    )
  end

  # ─── Tests ────────────────────────────────────────────────────────────────

  describe "POST /api/v1/checkouts" do
    context "when the user is not authenticated" do
      it "returns unauthorized" do
        post CHECKOUT_URL, params: { lookup_key: "creator_monthly" }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when the lookup key resolves no price" do
      before do
        sign_in(user)
        stub_price_list_empty
      end

      it "returns 404" do
        post CHECKOUT_URL, params: { lookup_key: "nonexistent_plan" }
        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body).to include("error")
      end
    end

    # ── First-time purchase (Free → Creator) ────────────────────────────────

    context "when the user has no active Stripe subscription (free tier)" do
      let(:checkout_session) { double("Stripe::Checkout::Session", url: "https://checkout.stripe.com/session123") }

      before do
        sign_in(user)
        stub_price_list(creator_price)
        # subscription exists but has no subscription_id (free tier)
        subscription.update_columns(subscription_id: nil, status: nil)
        allow(Stripe::Checkout::Session).to receive(:create).and_return(checkout_session)
      end

      it "creates a checkout session and returns the URL" do
        post CHECKOUT_URL, params: { lookup_key: "creator_monthly" }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["url"]).to eq("https://checkout.stripe.com/session123")
      end

      it "calls Stripe::Checkout::Session.create with correct params" do
        expect(Stripe::Checkout::Session).to receive(:create).with(
          hash_including(
            customer: stripe_customer_id,
            mode: "subscription",
            client_reference_id: user.id
          )
        ).and_return(checkout_session)

        post CHECKOUT_URL, params: { lookup_key: "creator_monthly" }
      end
    end

    # ── Same plan purchase blocked ──────────────────────────────────────────

    context "when the user tries to buy the same plan they already have" do
      let(:stripe_sub) do
        current_price = double("current_price", id: creator_price_id, unit_amount: 900)
        item = double("item", price: current_price, id: "si_item123")
        double("Stripe::Subscription",
               id: "sub_existing",
               items: double("items", data: [ item ]),
               status: "active")
      end

      before do
        sign_in(user)
        stub_price_list(creator_price)
        subscription.update_columns(subscription_id: "sub_existing", status: "active")
        allow(Stripe::Subscription).to receive(:retrieve).with("sub_existing").and_return(stripe_sub)
      end

      it "returns 422 with an error message" do
        post CHECKOUT_URL, params: { lookup_key: "creator_monthly" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to eq("You are already subscribed to this plan")
      end

      it "does not create a new checkout session" do
        expect(Stripe::Checkout::Session).not_to receive(:create)
        post CHECKOUT_URL, params: { lookup_key: "creator_monthly" }
      end
    end

    # ── Upgrade (Creator → Business) ────────────────────────────────────────

    context "when the user upgrades from Creator to Business" do
      let(:stripe_sub) do
        current_price = double("current_price", id: creator_price_id, unit_amount: 900)
        item = double("item", price: current_price, id: "si_item123")
        double("Stripe::Subscription",
               id: "sub_existing",
               items: double("items", data: [ item ]),
               status: "active")
      end

      let(:updated_sub) { double("Stripe::Subscription") }

      before do
        sign_in(user)
        stub_price_list(business_price)
        subscription.update_columns(subscription_id: "sub_existing", status: "active")
        allow(Stripe::Subscription).to receive(:retrieve).with("sub_existing").and_return(stripe_sub)
        allow(Stripe::Subscription).to receive(:update).and_return(updated_sub)
      end

      it "returns plan_changed with upgrade type" do
        post CHECKOUT_URL, params: { lookup_key: "business_monthly" }

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["status"]).to eq("plan_changed")
        expect(body["change_type"]).to eq("upgraded")
      end

      it "includes a message about immediate effect" do
        post CHECKOUT_URL, params: { lookup_key: "business_monthly" }

        body = response.parsed_body
        expect(body["message"]).to include("upgraded")
      end

      it "calls Stripe::Subscription.update with proration" do
        expect(Stripe::Subscription).to receive(:update).with(
          "sub_existing",
          hash_including(
            proration_behavior: "create_prorations",
            payment_behavior: "allow_incomplete",
            items: [ hash_including(price: business_price_id) ]
          )
        ).and_return(updated_sub)

        post CHECKOUT_URL, params: { lookup_key: "business_monthly" }
      end
    end

    # ── Downgrade (Business → Creator) ──────────────────────────────────────

    context "when the user downgrades from Business to Creator" do
      let(:stripe_sub) do
        current_price = double("current_price", id: business_price_id, unit_amount: 2900)
        item = double("item", price: current_price, id: "si_item123")
        double("Stripe::Subscription",
               id: "sub_existing",
               items: double("items", data: [ item ]),
               status: "active")
      end

      let(:updated_sub) { double("Stripe::Subscription") }

      before do
        sign_in(user)
        stub_price_list(creator_price)
        subscription.update_columns(subscription_id: "sub_existing", status: "active")
        allow(Stripe::Subscription).to receive(:retrieve).with("sub_existing").and_return(stripe_sub)
        allow(Stripe::Subscription).to receive(:update).and_return(updated_sub)
      end

      it "returns plan_changed with downgrade type" do
        post CHECKOUT_URL, params: { lookup_key: "creator_monthly" }

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["status"]).to eq("plan_changed")
        expect(body["change_type"]).to eq("downgraded")
      end

      it "calls Stripe::Subscription.update without proration" do
        expect(Stripe::Subscription).to receive(:update).with(
          "sub_existing",
          hash_including(
            proration_behavior: "none",
            payment_behavior: "allow_incomplete",
            items: [ hash_including(price: creator_price_id) ]
          )
        ).and_return(updated_sub)

        post CHECKOUT_URL, params: { lookup_key: "creator_monthly" }
      end

      it "includes a message about end-of-period changes" do
        post CHECKOUT_URL, params: { lookup_key: "creator_monthly" }

        body = response.parsed_body
        expect(body["message"]).to include("end of the current billing period")
      end
    end

    # ── Stripe API error ────────────────────────────────────────────────────

    context "when Stripe raises an error" do
      before do
        sign_in(user)
        stub_price_list(creator_price)
        subscription.update_columns(subscription_id: nil, status: nil)
        allow(Stripe::Checkout::Session).to receive(:create)
          .and_raise(Stripe::InvalidRequestError.new("Invalid price", "price"))
      end

      it "returns 400 with the error message" do
        post CHECKOUT_URL, params: { lookup_key: "creator_monthly" }

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body["error"]).to include("Invalid price")
      end
    end
  end

  # ─── Success / Cancel redirects ─────────────────────────────────────────

  describe "GET /api/v1/checkouts/success" do
    it "redirects to root path" do
      get "/api/v1/checkouts/success"
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "GET /api/v1/checkouts/cancel" do
    it "redirects to pricing page" do
      get "/api/v1/checkouts/cancel"
      expect(response).to redirect_to("/plans")
    end
  end
end
# rubocop:enable Metrics/BlockLength
