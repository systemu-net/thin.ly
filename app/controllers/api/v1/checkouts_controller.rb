module Api
  module V1
    class CheckoutsController < ApplicationController
      before_action :authenticate_user!, only: %i[create]
      skip_before_action :verify_authenticity_token, only: [ :create ]

      def create
        lookup_key = params["lookup_key"]
        prices = Stripe::Price.list(
          lookup_keys: [ lookup_key ],
          expand: [ "data.product" ]
        )

        new_price = prices.data[0]
        return render json: { error: "Plan not found for lookup key: #{lookup_key}" }, status: :not_found unless new_price

        subscription = current_user.subscriptions.first
        active_stripe_sub = subscription&.subscription_id

        # ── User already has an active Stripe subscription → upgrade / downgrade ──
        if active_stripe_sub.present? && subscription.status.in?(%w[active trialing past_due])
          handle_plan_change(subscription, active_stripe_sub, new_price)
        else
          # ── First purchase: create a Checkout Session ──
          create_checkout_session(new_price)
        end
      rescue Stripe::StripeError => e
        render json: { error: e.message }, status: :bad_request
      end

      def success
        redirect_to root_path, allow_other_host: true
      end

      def cancel
        redirect_to "/plans", allow_other_host: true
      end

      private

      def handle_plan_change(subscription, active_stripe_sub, new_price)
        stripe_sub = Stripe::Subscription.retrieve(active_stripe_sub)
        current_price_id = stripe_sub.items.data[0].price.id

        # ── Block same-plan purchase ──
        if current_price_id == new_price.id
          return render json: { error: "You are already subscribed to this plan" }, status: :unprocessable_entity
        end

        # Determine if this is an upgrade or downgrade by comparing unit amounts
        current_amount = stripe_sub.items.data[0].price.unit_amount || 0
        new_amount = new_price.unit_amount || 0
        upgrading = new_amount > current_amount

        # ── Upgrade: prorate immediately, Stripe auto-charges the payment method on file.
        #    If 3DS is needed, Stripe sends the customer an email to confirm.
        #    The webhook (customer.subscription.updated / invoice.paid) handles all state changes.
        # ── Downgrade: apply at end of current period so the customer keeps
        #    their higher-tier access until the period they already paid for ends.
        Stripe::Subscription.update(
          active_stripe_sub,
          items: [ {
            id: stripe_sub.items.data[0].id,
            price: new_price.id
          } ],
          proration_behavior: upgrading ? "create_prorations" : "none",
          payment_behavior: "allow_incomplete"
        )

        change_type = upgrading ? "upgraded" : "downgraded"
        render json: {
          status: "plan_changed",
          change_type: change_type,
          message: upgrading ?
            "Your plan has been upgraded. New limits are effective immediately." :
            "Your plan has been downgraded. Changes take effect at the end of the current billing period."
        }, status: :ok
      end

      def create_checkout_session(price)
        session = Stripe::Checkout::Session.create(
          customer: current_user.stripe_id,
          mode: "subscription",
          client_reference_id: current_user.id,
          line_items: [ {
            quantity: 1,
            price: price.id
          } ],
          success_url: api_v1_checkouts_success_url,
          cancel_url: api_v1_checkouts_cancel_url
        )

        render json: { url: session.url }, status: :ok
      end
    end
  end
end
