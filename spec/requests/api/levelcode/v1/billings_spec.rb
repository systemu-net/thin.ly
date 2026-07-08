require "rails_helper"

RSpec.describe "Api::Levelcode::V1::Billings", type: :request do
  BILLINGS_URL = "/api/levelcode/v1/billings"

  let(:user) { create(:user, stripe_id: "cus_test123") }
  let(:portal_session) { double(url: "https://billing.stripe.com/session/test_abc123") }

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: "cus_test123"))
    allow_any_instance_of(Api::Levelcode::V1::BaseController).to receive(:authenticate_levelcode!).and_return(true)
    allow_any_instance_of(Api::Levelcode::V1::BaseController).to receive(:current_user).and_return(user)
  end

  describe "POST /api/levelcode/v1/billings" do
    it "creates a Stripe billing portal session and returns the URL" do
      allow(Stripe::BillingPortal::Session).to receive(:create).and_return(portal_session)

      post BILLINGS_URL

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["url"]).to eq("https://billing.stripe.com/session/test_abc123")
    end

    it "passes the user's stripe_id and returns to SITE_ORIGIN/account" do
      allow(Stripe::BillingPortal::Session).to receive(:create).and_return(portal_session)

      post BILLINGS_URL

      expect(Stripe::BillingPortal::Session).to have_received(:create).with(
        hash_including(customer: user.stripe_id, return_url: a_string_matching(%r{/account\z}))
      )
    end

    it "returns 400 when Stripe raises an error" do
      allow(Stripe::BillingPortal::Session).to receive(:create)
        .and_raise(Stripe::StripeError.new("No such customer"))

      post BILLINGS_URL

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig("error", "message")).to include("No such customer")
    end
  end
end
