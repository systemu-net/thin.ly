# frozen_string_literal: true

module Levelcode
  # Change the plan on an EXISTING levelcode Stripe subscription (upgrade or downgrade), shared by the two
  # checkout entry points (Levelcode::WebController#checkout and Api::Levelcode::V1::CheckoutsController).
  # Both used to duplicate this logic; the downgrade path below is subtle enough that it must not drift
  # between them, so it lives here.
  #
  # UPGRADE (new price > current): swap the item price IMMEDIATELY with create_prorations — Stripe charges
  # the prorated difference on the payment method on file (Stripe emails a 3DS step if needed) and the
  # customer.subscription.updated webhook re-provisions the wallet UP right away. Levelcode::WebhookSync
  # sends the upgrade email, because it observes the change actually landing. Any attached schedule (a
  # pending deferred downgrade) is RELEASED first, so it can't reject the update or flip the price back
  # down at the boundary.
  #
  # DOWNGRADE (new price <= current): do NOT swap the item price now. Swapping immediately — even with
  # proration_behavior "none", which only defers the *charge* — drops the item to the cheaper price on the
  # Stripe object AT ONCE. customer.subscription.updated then fires and WebhookSync re-provisions the wallet
  # DOWN mid-period, so a customer who already paid for Ultra loses Ultra's allowance the moment they click
  # "downgrade" (and plan_key gates the model roster too, not just the caps). Instead we attach a Stripe
  # SubscriptionSchedule: the CURRENT (higher) price runs until the period they already paid for ends, then
  # the new price takes over at the boundary. The subscription keeps reporting the higher price until then,
  # so every mid-period webhook sees the higher plan and the wallet keeps its full entitlement — no webhook
  # guard or pending-downgrade state required. Because the downgrade is DEFERRED and scheduled HERE (the
  # webhook never observes it as an immediate flip), this service announces it to the customer.
  class PlanChange
    # Raised when the requested price is the plan the subscription is already on — the controllers turn this
    # into a 422 already_subscribed. Everything else that can go wrong is a Stripe::StripeError, which the
    # controllers already rescue.
    SamePlanError = Class.new(StandardError)

    Result = Struct.new(:change_type, :message, keyword_init: true)

    UPGRADE_MESSAGE =
      "Your plan is upgraded — the new limits are effective now, and you were charged only the " \
      "prorated difference for the rest of this billing period."
    DOWNGRADE_MESSAGE =
      "Your plan will change at the end of your current billing period. You keep your current plan " \
      "and its limits until then."

    def self.call(...)
      new(...).call
    end

    # user:            the buyer (for the downgrade notification email)
    # subscription_id: the Stripe subscription to modify (the caller already checked it's active)
    # new_price:       the target Stripe::Price (id, unit_amount, lookup_key)
    def initialize(user:, subscription_id:, new_price:)
      @user = user
      @subscription_id = subscription_id
      @new_price = new_price
    end

    def call
      stripe_sub = Stripe::Subscription.retrieve(@subscription_id)
      item = stripe_sub.items&.data&.first
      current_price = item&.price
      raise Stripe::InvalidRequestError.new("Subscription has no price item to change", "items") unless current_price

      raise SamePlanError if current_price.id == @new_price.id

      if upgrade?(current_price.unit_amount, @new_price.unit_amount)
        apply_upgrade(stripe_sub, item)
        Result.new(change_type: "upgraded", message: UPGRADE_MESSAGE)
      else
        effective_on = schedule_downgrade(stripe_sub, item, current_price)
        notify_downgrade(current_price.lookup_key, effective_on)
        Result.new(change_type: "downgraded", message: DOWNGRADE_MESSAGE)
      end
    end

    private

    # Only a real numeric increase is an upgrade — never prorate-charge off a nil price.
    def upgrade?(current_amount, new_amount)
      !current_amount.nil? && !new_amount.nil? && new_amount > current_amount
    end

    # Immediate, prorated swap on the same subscription (Stripe charges the difference now).
    def apply_upgrade(stripe_sub, item)
      release_schedule(stripe_sub)
      Stripe::Subscription.update(
        stripe_sub.id,
        items: [ { id: item.id, price: @new_price.id } ],
        proration_behavior: "create_prorations",
        payment_behavior: "allow_incomplete"
      )
    end

    # A previously scheduled (deferred) downgrade must not survive an upgrade: with the schedule still
    # attached, Stripe either rejects the direct Subscription.update or lets the schedule flip the price
    # at the boundary anyway — silently undoing the upgrade the customer just paid a proration for.
    # RELEASE (never cancel) detaches the schedule and leaves the subscription running on its current
    # item, which the update above then upgrades immediately.
    def release_schedule(stripe_sub)
      sched = stripe_sub.respond_to?(:schedule) ? stripe_sub.schedule : nil
      return if sched.blank?

      Stripe::SubscriptionSchedule.release(sched.is_a?(String) ? sched : sched.id)
    end

    # Attach (or reuse) a subscription schedule so the current price runs to period end and the new (lower)
    # price takes over at the boundary. Returns the DateTime the downgrade takes effect — the end of the
    # period the customer already paid for — for the notification email.
    def schedule_downgrade(stripe_sub, item, current_price)
      schedule = existing_schedule(stripe_sub) || Stripe::SubscriptionSchedule.create(from_subscription: stripe_sub.id)
      phase = current_phase(schedule)
      # The paid-through boundary. A fresh from_subscription schedule stamps it on the phase, but a
      # REUSED schedule's active phase can be OPEN-ENDED (our own final phase carries no end_date, so
      # once a first scheduled downgrade rolls past its boundary that phase is the active one) — the
      # item's current_period_end is the authoritative boundary either way. Time.at(nil) must never
      # happen here, and an end_date-less first phase would be an invalid schedule update.
      boundary = (phase && phase.end_date) || item.current_period_end

      Stripe::SubscriptionSchedule.update(
        schedule.id,
        # "release" hands the subscription back to normal billing once the schedule is done; NEVER "cancel",
        # which would end the subscription at the boundary instead of downgrading it.
        end_behavior: "release",
        proration_behavior: "none",
        phases: [
          {
            items: [ { price: current_price.id, quantity: 1 } ],
            start_date: (phase && phase.start_date) || item.current_period_start,
            end_date: boundary
          },
          {
            # No start_date → begins exactly when the current phase ends (the paid-through boundary). We pass
            # no end_date either, but Stripe still gives this final phase ONE billing cycle and then, per
            # end_behavior, RELEASES the subscription back to normal billing at the new price — where it goes
            # on renewing indefinitely. So "no end_date" means "one cycle, then released", not "runs forever
            # on the schedule". Verified against Stripe test mode with a test clock.
            items: [ { price: @new_price.id, quantity: 1 } ]
          }
        ]
      )

      Time.at(boundary).to_datetime
    end

    # The subscription may already carry a schedule (e.g. a prior deferred downgrade) — reuse it, since
    # Stripe rejects a second schedule on the same subscription.
    def existing_schedule(stripe_sub)
      sched = stripe_sub.respond_to?(:schedule) ? stripe_sub.schedule : nil
      return nil if sched.blank?

      Stripe::SubscriptionSchedule.retrieve(sched.is_a?(String) ? sched : sched.id)
    end

    # The phase covering "now" — for a fresh from_subscription schedule that's the only phase; for a reused
    # one it's whichever phase is currently active (never a completed phase, whose end_date is in the past
    # and which Stripe would reject as a phase boundary).
    def current_phase(schedule)
      now = Time.current.to_i
      schedule.phases.find { |ph| ph.start_date <= now && (ph.end_date.nil? || now < ph.end_date) } ||
        schedule.phases.first
    end

    # Best-effort downgrade notice from the request path. Best-effort for the same reason WebhookSync's
    # mailers are: a mailer/enqueue hiccup must not fail an otherwise-successful plan change. deliver_later
    # keeps SMTP off the request path.
    def notify_downgrade(current_lookup_key, effective_on)
      LevelcodeBillingMailer.with(
        user: @user,
        from_plan: Levelcode.plan(current_lookup_key),
        plan: Levelcode.plan(@new_price.lookup_key),
        plan_key: @new_price.lookup_key,
        direction: "downgrade",
        period_end: effective_on
      ).plan_changed.deliver_later
      Rails.logger.info("[Levelcode::PlanChange] Downgrade email queued for #{@user.email} " \
                        "(#{current_lookup_key}→#{@new_price.lookup_key}, effective #{effective_on})")
    rescue StandardError => e
      Rails.logger.error("[Levelcode::PlanChange] Downgrade email enqueue failed for #{@user.email}: " \
                         "#{e.class}: #{e.message}")
    end
  end
end
