module Levelcode
  # Provisions / resets a user's levelcode CreditWallet from Stripe subscription
  # events (SPEC §5, §6). Called from the EXISTING Api::V1::WebhooksController
  # for every event; it self-filters to the `levelcode` product and no-ops for
  # link-shortener (`linkly`) subscriptions, so the two products never collide.
  #
  # Handled events:
  #   checkout.session.completed  → provision wallet (first purchase)
  #   invoice.paid                → reset used counters + roll the period
  #   customer.subscription.updated → re-provision caps for the new plan
  #   customer.subscription.deleted → tear the wallet down to free
  #
  # Usage (wired by the orchestrator in webhooks_controller#handle_event):
  #   Levelcode::WebhookSync.call(event)
  class WebhookSync
    PRODUCT = "levelcode".freeze

    # Raised when a money-critical wallet sync fails AFTER Stripe idempotency was claimed. The webhook
    # controller releases the idempotency claim and returns non-2xx so Stripe RETRIES, rather than
    # silently stranding a teardown/provision (e.g. a canceled wallet left fully funded).
    SyncError = Class.new(StandardError)

    # Stripe failures worth a webhook retry: a network blip, rate limiting, or a Stripe-side 5xx
    # (Stripe::APIError). Everything else — InvalidRequestError, AuthenticationError, CardError, … —
    # is PERMANENT: retrying the same event can't help, so we ack it (200) instead of churning Stripe's
    # retry queue. (RateLimitError and APIError are direct StripeError subclasses in stripe 13.x.)
    TRANSIENT_STRIPE_ERRORS = [
      Stripe::APIConnectionError,
      Stripe::RateLimitError,
      Stripe::APIError
    ].freeze

    def self.call(event)
      new(event).call
    end

    def initialize(event)
      @event = event
      @object = event.data.object
    end

    def call
      case @event.type
      when "checkout.session.completed"
        return unless @object.mode == "subscription"
        provision_from_subscription_id(@object.subscription, @object.customer)
      when "invoice.paid", "invoice.payment_succeeded"
        provision_from_invoice(@object, reset_usage: true)
      when "customer.subscription.updated"
        provision_from_stripe_subscription(@object, @object.customer)
      when "customer.subscription.deleted"
        teardown(@object.customer)
      end
    rescue Stripe::StripeError => e
      Rails.logger.error("[Levelcode::WebhookSync] Stripe error on #{@event.type}: #{e.class}: #{e.message}")
      # Transient (network / rate-limit / Stripe 5xx) → re-raise so the controller releases idempotency
      # and returns non-2xx; Stripe redelivers (bounded to ~3 days) and the sync re-runs. Permanent
      # errors fall through and are swallowed → 200 (retrying can't help).
      raise SyncError, "#{e.class}: #{e.message}" if TRANSIENT_STRIPE_ERRORS.any? { |klass| e.is_a?(klass) }
    end

    private

    # ── Resolvers ─────────────────────────────────────────────────

    def provision_from_invoice(invoice, reset_usage:)
      # Stripe API 2024-12-18 moved subscription onto invoice.parent.subscription_details;
      # older/replayed events still carry invoice.subscription. Try modern, then legacy.
      subscription_id = invoice.parent&.subscription_details&.subscription
      subscription_id = invoice.try(:subscription) if subscription_id.blank?
      return if subscription_id.blank?

      provision_from_subscription_id(subscription_id, invoice.customer, reset_usage: reset_usage)
    end

    def provision_from_subscription_id(subscription_id, customer_id, reset_usage: false)
      return if subscription_id.blank?

      stripe_subscription = Stripe::Subscription.retrieve(subscription_id)
      provision_from_stripe_subscription(stripe_subscription, customer_id, reset_usage: reset_usage)
    end

    def provision_from_stripe_subscription(stripe_subscription, customer_id, reset_usage: false)
      lookup_key = lookup_key_for(stripe_subscription)
      return unless levelcode_plan?(lookup_key)

      user = find_user(customer_id)
      return unless user

      # Only an ACTIVE/TRIALING subscription funds the wallet. A past_due/unpaid/incomplete/paused sub
      # must NOT (re)provision the paid budget — otherwise a failed renewal keeps paying-tier credits.
      # (A definitive cancel arrives as customer.subscription.deleted → teardown; grace-expiry in
      # FreeTier is the backstop if that webhook is ever missed.)
      status = stripe_subscription.respond_to?(:status) ? stripe_subscription.status.to_s : "active"
      unless %w[active trialing].include?(status)
        Rails.logger.info("[Levelcode::WebhookSync] Sub status=#{status} for #{user.email} — not (re)provisioning the paid budget")
        return
      end

      plan = Levelcode.plan(lookup_key)
      unless plan
        Rails.logger.warn("[Levelcode::WebhookSync] No Levelcode plan for lookup_key=#{lookup_key}")
        return
      end

      item = stripe_subscription.items.data[0]
      period_start = Time.at(item.current_period_start).to_datetime
      period_end   = Time.at(item.current_period_end).to_datetime

      wallet = CreditWallet.find_or_initialize_by(user: user, product: PRODUCT)

      # Treat an ADVANCING period_end as a fresh billing period (roll) and reset the metered counters —
      # even on customer.subscription.updated — so the prior period's spend can't enforce against the
      # new one. A same-period update (card change, cancel toggle) leaves spend untouched.
      period_advanced = wallet.period_end.blank? || period_end > wallet.period_end
      did_reset = reset_usage || wallet.new_record? || period_advanced

      attrs = {
        plan_key: lookup_key,
        input_cap: plan[:input_cap],
        output_cap: plan[:output_cap],
        # M14: the enforced allowance is the DOLLAR budget (revenue-based fraction for the tier).
        budget_micros: Levelcode.budget_micros(lookup_key),
        period_start: period_start,
        period_end: period_end,
        overage_policy: plan[:overage_policy] || wallet.overage_policy || "throttle"
      }
      if did_reset
        attrs[:input_used] = 0
        attrs[:output_used] = 0
        attrs[:spent_micros] = 0
      end

      wallet.update!(attrs)
      # Wipe the hot counters on a reset too — a reset that reuses the same period_end epoch would
      # otherwise resurrect the pre-reset spend via max(Redis, durable).
      Levelcode::Metering.clear!(wallet) if did_reset
      Rails.logger.info("[Levelcode::WebhookSync] Wallet synced for #{user.email} (plan=#{lookup_key}, reset=#{did_reset})")
    end

    def teardown(customer_id)
      user = find_user(customer_id)
      return unless user

      wallet = CreditWallet.find_by(user: user, product: PRODUCT)
      return unless wallet

      wallet.update!(
        plan_key: "free",
        input_cap: 0,
        output_cap: 0,
        budget_micros: 0, # zeroed → FreeTier re-provisions the free budget on next gateway access
        spent_micros: 0,
        input_used: 0,
        output_used: 0
      )
      Levelcode::Metering.clear!(wallet) # drop stale hot counters so they can't resurrect spend
      Rails.logger.info("[Levelcode::WebhookSync] Wallet reset to free for #{user.email}")
    end

    # ── Helpers ───────────────────────────────────────────────────

    # The Stripe subscription's price carries the frozen lookup_key
    # (orbits_pro, orbits_pro_plus, …). We key Levelcode::PLANS off it.
    def lookup_key_for(stripe_subscription)
      stripe_subscription.items.data[0]&.price&.lookup_key
    end

    def levelcode_plan?(lookup_key)
      lookup_key.present? && Levelcode.plan(lookup_key).present?
    end

    def find_user(customer_id)
      user = User.find_by(stripe_id: customer_id)
      Rails.logger.error("[Levelcode::WebhookSync] User not found for stripe customer: #{customer_id}") unless user
      user
    end
  end
end
