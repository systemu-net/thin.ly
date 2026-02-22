module Api
  module V1
    class BillingsController < ApplicationController
      before_action :authenticate_user!, only: %i[create]
      skip_before_action :verify_authenticity_token

      def create
        begin
          session = Stripe::BillingPortal::Session.create({
            customer: current_user.stripe_id,
            return_url: root_url
          })
        rescue => e
          return render json: { 'error': { message: e.error.message } }.to_json, status: 400
        end

        render json: { url: session.url }.to_json, status: 200
      end
    end
  end
end
