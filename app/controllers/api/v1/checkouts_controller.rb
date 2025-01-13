module Api
  module V1
    class CheckoutsController < ApplicationController
      before_action :authenticate_user!, only: %i[create]
      skip_before_action :verify_authenticity_token, only: [ :create ]
      # before_action :set_link, only: %i[lookup_code show update destroy]

      def create
        prices = Stripe::Price.list(
          lookup_keys: [ params["lookup_key"] ],
          expand: [ "data.product" ]
        )

        begin
          session = Stripe::Checkout::Session.create(
            customer: current_user.stripe_id,
            mode: "subscription",
            # automatic_tax: { enabled: true },
            line_items: [ {
              quantity: 1,
              price: prices.data[0].id
            } ],
            success_url: api_v1_checkouts_success_url,
            cancel_url: api_v1_checkouts_cancel_url
          )
        rescue => e
          render json: { 'error': { message: e.error.message } }.to_json, status: 400
        end

        render json: { url: session.url }.to_json, status: 200
      end

      def success
        redirect_to ENV["DEV_HOST"] + "/", allow_other_host: true
      end

      def cancel
        redirect_to ENV["DEV_HOST"] + "/_pricing", allow_other_host: true
      end
    end
  end
end
