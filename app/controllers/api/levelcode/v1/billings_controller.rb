module Api
  module Levelcode
    module V1
      # Stripe billing portal for the levelcode product.
      # Mirrors Api::V1::BillingsController, but returns the customer to the
      # site account page (SITE_ORIGIN/account) after they manage billing.
      class BillingsController < BaseController
        # POST /api/levelcode/v1/billings
        def create
          begin
            session = Stripe::BillingPortal::Session.create({
              customer: current_user.stripe_id,
              return_url: "#{site_origin}/account"
            })
          rescue => e
            return render json: { error: { code: "stripe_error", message: e.message } }, status: :bad_request
          end

          render json: { url: session.url }, status: :ok
        end

        private

        def site_origin
          ENV["SITE_ORIGIN"] || "https://levelcode.ai"
        end
      end
    end
  end
end
