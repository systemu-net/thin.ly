class Api::V1::WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [ :create ]

  # POST /api/v1/webhooks — receive webhook events from Stripe
  def create
    payload = request.body.read
    signature_header = request.env["HTTP_STRIPE_SIGNATURE"]
    endpoint_secret = ENV["STRIPE_WEBHOOK_SIGNING_SECRET"] || Rails.application.credentials.dig(:stripe_webhook_signing_secret)

    begin
      event = Stripe::Webhook.construct_event(payload, signature_header, endpoint_secret)
    rescue JSON::ParserError => e
      Rails.logger.error("[Stripe Webhook] JSON Parse Error: #{e.message}")
      return render json: { error: "Invalid payload" }, status: 400
    rescue Stripe::SignatureVerificationError => e
      Rails.logger.error("[Stripe Webhook] Signature Verification Failed: #{e.message}")
      return render json: { error: "Invalid signature" }, status: 400
    end

    Rails.logger.info("[Stripe Webhook] Received: #{event.type} (#{event.id})")

    begin
      # Claim idempotency up-front so that only one process handles a given Stripe event.
      ProcessedStripeEvent.mark_as_processed!(event.id, event.type)
    rescue ActiveRecord::RecordNotUnique
      Rails.logger.info("[Stripe Webhook] Skipping duplicate: #{event.id}")
      return head :ok
    end

    handle_event(event)
    head :ok
  rescue => e
    Rails.logger.error("[Stripe Webhook] Unhandled error processing #{event&.type}: #{e.message}")
    Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
    head :ok # Always return 200 so Stripe doesn't retry indefinitely
  end

  private

  # ─── Event Router ───────────────────────────────────────────────

  def handle_event(event)
    obj = event.data.object

    case event.type

    # ── Checkout Session Events ──────────────────────────────────
    when "checkout.session.completed"
      # Initial checkout succeeded. For card payments the invoice is already paid,
      # so invoice.paid handles fulfillment. We only log here.
      Rails.logger.info("[Stripe Webhook] Checkout completed: #{obj.id}, customer: #{obj.customer}")

    when "checkout.session.async_payment_succeeded"
      # Delayed payment method (e.g. bank debit) confirmed after checkout.
      # invoice.paid fires separately and handles fulfillment.
      Rails.logger.info("[Stripe Webhook] Async payment succeeded: #{obj.id}, customer: #{obj.customer}")

    when "checkout.session.async_payment_failed"
      # Delayed payment method failed after checkout.
      handle_payment_failed(obj.customer)

    # ── Invoice Events ───────────────────────────────────────────
    when "invoice.paid"
      # The single source of truth for all successful subscription payments.
      # Fires for initial purchase, renewals, and out-of-band payments.
      handle_invoice_paid(obj)

    when "invoice.payment_succeeded"
      # Contains the same data as invoice.paid but does NOT fire for out-of-band
      # payments. Since we handle invoice.paid, we only log here to avoid duplication.
      Rails.logger.info("[Stripe Webhook] invoice.payment_succeeded: #{obj.id} (handled by invoice.paid)")

    when "invoice.payment_failed"
      # A payment attempt on an invoice failed.
      handle_payment_failed(obj.customer)

    when "invoice.payment_action_required"
      # Customer needs to complete an action (e.g. 3D Secure authentication).
      handle_payment_action_required(obj)

    # ── Subscription Events ──────────────────────────────────────
    when "customer.subscription.updated"
      # Plan change, status change, or trial update.
      handle_subscription_updated(obj)

    when "customer.subscription.deleted"
      # Subscription was canceled or expired.
      handle_subscription_deleted(obj)

    when "customer.subscription.trial_will_end"
      # Trial ends in ~3 days. Send a heads-up email.
      handle_trial_will_end(obj)

    else
      Rails.logger.warn("[Stripe Webhook] Unhandled event type: #{event.type}")
    end
  end

  # ─── Invoice Handlers ──────────────────────────────────────────

  def handle_invoice_paid(invoice)
    # Stripe API 2024-12-18 moved subscription to invoice.parent.subscription_details,
    # but older events (replays, test clocks) and some edge cases still use invoice.subscription.
    # Try the modern path first, fall back to legacy, and only skip if both are blank.
    subscription_id = invoice.parent&.subscription_details&.subscription
    subscription_id = invoice.try(:subscription) if subscription_id.blank?

    unless subscription_id.present?
      Rails.logger.info("[Stripe Webhook] invoice.paid is not subscription-related, skipping")
      return
    end

    user = find_user_by_stripe_id(invoice.customer)
    return unless user

    stripe_subscription = Stripe::Subscription.retrieve(subscription_id)
    subscription = Subscription.find_by(customer_id: user.stripe_id)
    unless subscription
      Rails.logger.error("[Stripe Webhook] Subscription not found for customer: #{user.stripe_id}")
      return
    end

    sync_subscription(subscription, stripe_subscription)

    invoice_data = extract_invoice_data(invoice, stripe_subscription)

    # Send the right email: first payment vs recurring renewal
    if invoice.billing_reason == "subscription_create"
      SubscriptionMailer.with(user: user, invoice_data: invoice_data).payment_completed.deliver_now
    else
      SubscriptionMailer.with(user: user, invoice_data: invoice_data).payment_successful.deliver_now
    end

    Rails.logger.info("[Stripe Webhook] invoice.paid processed for #{user.email} (reason: #{invoice.billing_reason})")
  end

  def handle_payment_action_required(invoice)
    user = find_user_by_stripe_id(invoice.customer)
    return unless user

    # The hosted_invoice_url lets the customer complete authentication
    Rails.logger.warn(
      "[Stripe Webhook] Payment action required for #{user.email}. " \
      "Invoice: #{invoice.id}, URL: #{invoice.hosted_invoice_url}"
    )

    SubscriptionMailer.with(user: user, url: invoice.hosted_invoice_url).payment_action_required.deliver_now
  end

  # ─── Subscription Handlers ─────────────────────────────────────

  def handle_subscription_updated(stripe_subscription)
    user = find_user_by_stripe_id(stripe_subscription.customer)
    return unless user

    subscription = Subscription.find_by(subscription_id: stripe_subscription.id) ||
                   Subscription.find_by(customer_id: user.stripe_id)

    unless subscription
      Rails.logger.error(
        "[Stripe Webhook] Subscription not found for subscription: #{stripe_subscription.id}, " \
        "customer: #{user.stripe_id}"
      )
      return
    end

    # Track cancel_at_period_end changes (set via Stripe billing portal or API)
    was_canceling = subscription.cancel_at_period_end?
    is_canceling = stripe_subscription.cancel_at_period_end

    sync_subscription(subscription, stripe_subscription)

    # Notify user when cancellation is scheduled or reactivated
    if !was_canceling && is_canceling
      Rails.logger.info("[Stripe Webhook] Subscription scheduled to cancel at period end for #{user.email}")
      # TODO: SubscriptionMailer.with(user: user, period_end: subscription.current_period_end).cancellation_scheduled.deliver_now
    elsif was_canceling && !is_canceling
      Rails.logger.info("[Stripe Webhook] Subscription reactivated for #{user.email}")
      # TODO: SubscriptionMailer.with(user: user).subscription_reactivated.deliver_now
    end

    Rails.logger.info(
      "[Stripe Webhook] Subscription updated for #{user.email}: " \
      "status=#{stripe_subscription.status}, cancel_at_period_end=#{is_canceling}, id=#{stripe_subscription.id}"
    )
  end

  def handle_subscription_deleted(stripe_subscription)
    user = find_user_by_stripe_id(stripe_subscription.customer)
    return unless user

    subscription = user.subscriptions.find_by(subscription_id: stripe_subscription.id)
    unless subscription
      Rails.logger.error("[Stripe Webhook] Subscription to cancel not found: #{stripe_subscription.id}")
      return
    end

    subscription.update(
      status: "canceled",
      subscription_id: nil,
      stripe_price_id: nil,
      cancel_at_period_end: false
    )
    subscription.plan.update(Plan::DEFAULT_PLAN)

    SubscriptionMailer.with(user: user).subscription_canceled.deliver_now
    Rails.logger.info("[Stripe Webhook] Subscription canceled for #{user.email}")
  end

  def handle_trial_will_end(stripe_subscription)
    user = find_user_by_stripe_id(stripe_subscription.customer)
    return unless user

    trial_end = Time.at(stripe_subscription.trial_end).to_datetime
    Rails.logger.info("[Stripe Webhook] Trial ending on #{trial_end} for #{user.email}")

    # TODO: send a trial-ending-soon email
    # SubscriptionMailer.with(user: user, trial_end: trial_end).trial_will_end.deliver_now
  end

  # ─── Shared Helpers ─────────────────────────────────────────────

  def handle_payment_failed(customer_id)
    user = find_user_by_stripe_id(customer_id)
    return unless user

    SubscriptionMailer.with(user: user).payment_failed.deliver_now
    Rails.logger.info("[Stripe Webhook] Payment failed email sent to #{user.email}")
  end

  def find_user_by_stripe_id(stripe_customer_id)
    user = User.find_by(stripe_id: stripe_customer_id)
    unless user
      Rails.logger.error("[Stripe Webhook] User not found for stripe customer: #{stripe_customer_id}")
    end
    user
  end

  def sync_subscription(subscription, stripe_subscription)
    item = stripe_subscription.items.data[0]
    stripe_plan = item.plan

    # Fetch product metadata before opening the transaction so that a Stripe API
    # failure here does not roll back the subscription sync that follows.
    stripe_product = stripe_plan.product
    metadata = nil
    begin
      metadata = Stripe::Product.retrieve(stripe_product).metadata.as_json
    rescue Stripe::StripeError => e
      Rails.logger.error("[Stripe Webhook] Could not retrieve product #{stripe_product}: #{e.message}")
    end

    ActiveRecord::Base.transaction do
      # Always sync subscription-level data regardless of product metadata
      subscription.update!(
        current_period_start: Time.at(item.current_period_start).to_datetime,
        current_period_end: Time.at(item.current_period_end).to_datetime,
        interval: stripe_plan.interval,
        status: stripe_subscription.status,
        subscription_id: stripe_subscription.id,
        stripe_price_id: item.price&.id,
        cancel_at_period_end: stripe_subscription.cancel_at_period_end || false
      )

      # Sync plan limits from Stripe product metadata
      unless metadata.present?
        # nil means the API call failed (already logged); empty hash means no metadata on the product
        Rails.logger.error("[Stripe Webhook] No metadata on product: #{stripe_product}") if metadata
        return
      end

      subscription.plan.update!(
        name: metadata["name"],
        links: metadata["links"].to_i,
        qr_codes: metadata["qr_codes"].to_i,
        brand_pages: metadata["brand_pages"].to_i
      )
    end
  end

  # Build a hash of invoice details for email templates and PDF attachment.
  # Gracefully handles missing fields so the email still sends even if
  # some data is unavailable.
  def extract_invoice_data(invoice, stripe_subscription)
    item = stripe_subscription.items.data[0]
    amount_cents = invoice.respond_to?(:amount_paid) ? invoice.amount_paid : nil
    currency = invoice.respond_to?(:currency) ? invoice.currency&.upcase : "USD"

    # Try to get card last4 from the charge's payment method
    card_last4 = nil
    begin
      if invoice.respond_to?(:charge) && invoice.charge.present?
        charge = Stripe::Charge.retrieve(invoice.charge)
        card_last4 = charge.payment_method_details&.card&.last4
      end
    rescue StandardError => e
      Rails.logger.warn("[Stripe Webhook] Could not retrieve card details: #{e.message}")
    end

    {
      plan_name: item&.plan&.nickname || item&.price&.nickname,
      amount_paid: amount_cents ? format_amount(amount_cents, currency) : nil,
      card_last4: card_last4,
      period_end: item&.current_period_end ? Time.at(item.current_period_end).strftime("%B %d, %Y") : nil,
      invoice_pdf: invoice.respond_to?(:invoice_pdf) ? invoice.invoice_pdf : nil
    }
  rescue StandardError => e
    Rails.logger.warn("[Stripe Webhook] Failed to extract invoice data: #{e.message}")
    {}
  end

  def format_amount(cents, currency = "USD")
    amount = cents / 100.0
    "$#{'%.2f' % amount} #{currency}"
  end
end
