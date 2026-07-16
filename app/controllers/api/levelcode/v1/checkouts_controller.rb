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
            handle_plan_change(active_stripe_sub, new_price)
          else
            # ── First purchase: create a Checkout Session ──
            create_checkout_session(new_price)
          end
        rescue Stripe::StripeError => e
          render json: { error: { code: "stripe_error", message: e.message } }, status: :bad_request
        end

        private

        # Upgrade → immediate prorated swap; downgrade → a subscription schedule that keeps the current,
        # higher tier until period end (see Levelcode::PlanChange for why). The webhook syncs the wallet and
        # announces the immediate upgrade; the service announces the scheduled downgrade.
        def handle_plan_change(active_stripe_sub, new_price)
          result = ::Levelcode::PlanChange.call(
            user: current_user, subscription_id: active_stripe_sub, new_price: new_price
          )
          render json: {
            status: "plan_changed",
            change_type: result.change_type,
            message: result.message
          }, status: :ok
        rescue ::Levelcode::PlanChange::SamePlanError
          render json: { error: { code: "already_subscribed", message: "You are already subscribed to this plan" } }, status: :unprocessable_content
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
