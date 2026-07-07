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
      Rails.logger.error("[Levelcode::WebhookSync] Stripe error on #{@event.type}: #{e.message}")
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

      plan = Levelcode.plan(lookup_key)
      unless plan
        Rails.logger.warn("[Levelcode::WebhookSync] No Levelcode plan for lookup_key=#{lookup_key}")
        return
      end

      item = stripe_subscription.items.data[0]
      period_start = Time.at(item.current_period_start).to_datetime
      period_end   = Time.at(item.current_period_end).to_datetime

      wallet = CreditWallet.find_or_initialize_by(user: user, product: PRODUCT)
      attrs = {
        plan_key: lookup_key,
        input_cap: plan[:input_cap],
        output_cap: plan[:output_cap],
        # M14: the enforced allowance is the DOLLAR budget (flagship worst-case for the tier).
        budget_micros: Levelcode.budget_micros(lookup_key),
        period_start: period_start,
        period_end: period_end,
        overage_policy: plan[:overage_policy] || wallet.overage_policy || "throttle"
      }
      # Reset the metered counters on a fresh billing period (invoice.paid) or
      # when the wallet is first provisioned.
      if reset_usage || wallet.new_record?
        attrs[:input_used] = 0
        attrs[:output_used] = 0
        attrs[:spent_micros] = 0
      end

      wallet.update!(attrs)
      Rails.logger.info("[Levelcode::WebhookSync] Wallet synced for #{user.email} (plan=#{lookup_key}, reset=#{reset_usage || wallet.previously_new_record?})")
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
