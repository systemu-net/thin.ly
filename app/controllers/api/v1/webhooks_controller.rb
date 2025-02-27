class Api::V1::WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [ :create ]

  # receive POST from Stripe
  def create
    # docs: https://stripe.com/docs/payments/checkout/fulfill-orders
    payload = request.body.read
    signature_header = request.env["HTTP_STRIPE_SIGNATURE"]
    endpoint_secret = ENV["STRIPE_WEBHOOK_SIGNING_SECRET"] || Rails.application.credentials.dig(:stripe_webhook_signing_secret)
    event = nil

    begin
      event = Stripe::Webhook.construct_event(
        payload, signature_header, endpoint_secret
      )
    rescue JSON::ParserError => e
      render json: { message: e }, status: 400
      return
    rescue Stripe::SignatureVerificationError => e
      render json: { message: e }, status: 400
      return
    end

    case event.type
    when "checkout.session.completed"
      user = User.find_by(stripe_id: event.data.object.customer)
      fullfill_order(event.data.object)
      if user.retrieve_stripe_customer
        SubscriptionMailer.with(user: user).payment_completed.deliver_now
      end
    when "checkout.session.async_payment_succeeded"
      # Some payments take longer to succeed (usually noncredit card payments)
    when "invoice.payment_succeeded"
      return unless event.data.object.subscription.present?
      user = User.find_by(stripe_id: event.data.object.customer)
      stripe_subscription = Stripe::Subscription.retrieve(event.data.object.subscription)
      subscription = Subscription.find_by(subscription_id: stripe_subscription)

      subscription.update(
        current_period_start: Time.at(stripe_subscription.current_period_start).to_datetime,
        current_period_end: Time.at(stripe_subscription.current_period_end).to_datetime,
        # plan: stripe_subscription.plan.id,
        interval: stripe_subscription.plan.interval,
        status: stripe_subscription.status,
      )

      if user.retrieve_stripe_customer
        SubscriptionMailer.with(user: user).payment_successful.deliver_now
      end
    when "invoice.payment_failed"
      user = User.find_by(stripe_id: event.data.object.customer)
      if user.retrieve_stripe_customer
        SubscriptionMailer.with(user: user).payment_failed.deliver_now
      end
    else
      puts "Unhandled event type: #{event.type}"
    end
  end

  private

  def fullfill_order(checkout_session)
    # Find user and assign customer id from Stripe
    user = User.find(checkout_session.client_reference_id)
    user.update(stripe_id: checkout_session.customer)

    # Retrieve new subscription via Stripe API using susbscription id
    stripe_subscription = Stripe::Subscription.retrieve(checkout_session.subscription)

    product_plan = stripe_subscription.plan.product
    metadata = Stripe::Product.retrieve(product_plan).metadata.as_json

    subscription = Subscription.find_by(customer_id: stripe_subscription.customer)
    # Update existing subscription with Stripe subscription details and user data
    subscription.update(
      current_period_start: Time.at(stripe_subscription.current_period_start).to_datetime,
      current_period_end: Time.at(stripe_subscription.current_period_end).to_datetime,
      # plan: stripe_subscription.plan.id,
      interval: stripe_subscription.plan.interval,
      status: stripe_subscription.status,
      subscription_id: stripe_subscription.id
    )

    subscription.plan.update(
      name: metadata["name"],
      links: metadata["links"].to_i,
      qr_codes: metadata["qr_codes"].to_i,
      pages: metadata["pages"].to_i
    )
  end
end
