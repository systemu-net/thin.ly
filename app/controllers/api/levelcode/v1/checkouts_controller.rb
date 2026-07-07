module Api
  module Levelcode
    module V1
      # Stripe Checkout / plan-change for the `levelcode` product.
      # Mirrors Api::V1::CheckoutsController's checkout + proration pattern, but
      # scoped to the levelcode product subscription and redirecting to the site
      # account page (SITE_ORIGIN/account) rather than the link-shortener routes.
      class CheckoutsController < BaseController
        PRODUCT = "levelcode".freeze

        # POST /api/levelcode/v1/checkouts
        def create
          lookup_key = params["lookup_key"]
          prices = Stripe::Price.list(
            lookup_keys: [ lookup_key ],
            expand: [ "data.product" ]
          )

          new_price = prices.data[0]
          return render json: { error: { code: "plan_not_found", message: "Plan not found for lookup key: #{lookup_key}" } }, status: :not_found unless new_price

          subscription = current_user.subscriptions.find_by(product: PRODUCT)
          active_stripe_sub = subscription&.subscription_id

          # ── User already has an active levelcode subscription → upgrade / downgrade ──
          if active_stripe_sub.present? && subscription&.status&.in?(%w[active trialing past_due])
            handle_plan_change(subscription, active_stripe_sub, new_price)
          else
            # ── First purchase: create a Checkout Session ──
            create_checkout_session(new_price)
          end
        rescue Stripe::StripeError => e
          render json: { error: { code: "stripe_error", message: e.message } }, status: :bad_request
        end

        private

        def handle_plan_change(subscription, active_stripe_sub, new_price)
          stripe_sub = Stripe::Subscription.retrieve(active_stripe_sub)
          current_price_id = stripe_sub.items.data[0].price.id

          # ── Block same-plan purchase ──
          if current_price_id == new_price.id
            return render json: { error: { code: "already_subscribed", message: "You are already subscribed to this plan" } }, status: :unprocessable_content
          end

          # Determine if this is an upgrade or downgrade by comparing unit amounts
          current_amount = stripe_sub.items.data[0].price.unit_amount
          new_amount = new_price.unit_amount
          upgrading =
            if current_amount.nil? || new_amount.nil?
              # If either price has no unit_amount, avoid treating this as an upgrade based on a bogus comparison.
              false
            else
              new_amount > current_amount
            end

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
            success_url: "#{site_origin}/account?checkout=success",
            cancel_url: "#{site_origin}/account?checkout=cancel"
          )

          render json: { url: session.url }, status: :ok
        end

        def site_origin
          ENV["SITE_ORIGIN"] || "https://levelcode.ai"
        end
      end
    end
  end
end
