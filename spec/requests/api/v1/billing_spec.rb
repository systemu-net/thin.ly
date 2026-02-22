require 'rails_helper'

RSpec.describe "Api::V1::Billings", type: :request do
  let(:user) { create(:user) }
  let(:portal_session) { double(url: 'https://billing.stripe.com/session/test_abc123') }

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: 'cus_test123'))
  end

  describe "POST /api/v1/billings" do
    context "when user is authenticated" do
      before { sign_in user }

      it "creates a Stripe billing portal session and returns the URL" do
        allow(Stripe::BillingPortal::Session).to receive(:create).and_return(portal_session)

        post "/api/v1/billings", headers: auth_headers(user)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['url']).to eq('https://billing.stripe.com/session/test_abc123')
      end

      it "passes the current user's stripe_id as customer" do
        allow(Stripe::BillingPortal::Session).to receive(:create).and_return(portal_session)

        post "/api/v1/billings", headers: auth_headers(user)

        expect(Stripe::BillingPortal::Session).to have_received(:create).with(
          hash_including(customer: user.stripe_id)
        )
      end

      it "returns 400 when Stripe raises an error" do
        error_obj = double(message: 'No such customer')
        stripe_error = Stripe::StripeError.new('No such customer')
        stripe_error.define_singleton_method(:error) { error_obj }
        allow(Stripe::BillingPortal::Session).to receive(:create).and_raise(stripe_error)

        post "/api/v1/billings", headers: auth_headers(user)

        expect(response).to have_http_status(:bad_request)
      end
    end

    context "when user is not authenticated" do
      it "returns unauthorized status" do
        post "/api/v1/billings"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
