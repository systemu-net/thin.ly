# frozen_string_literal: true

module Levelcode
  # Free tier (M11): a logged-in, not-yet-paid editor user gets gateway access on
  # the cheap open-weights engine (Levelcode::FREE_MODEL). This provisions — and
  # lazily rolls each month — a "free" plan CreditWallet, which is the metering
  # anchor. It NEVER touches a real paid plan (that's the Stripe webhook's job).
  module FreeTier
    module_function

    PRODUCT = "levelcode"

    # The user's levelcode wallet: their PAID plan if active, otherwise a fresh (or
    # month-rolled) free wallet. Always returns a persisted wallet. Idempotent.
    #
    # Concurrency: a brand-new wallet is created optimistically (the (user, product)
    # unique index + the RecordNotUnique rescue serialize the INSERT race). An EXISTING
    # wallet is (re)checked and rolled UNDER A ROW LOCK (with_lock → SELECT … FOR UPDATE,
    # which reloads), so a concurrent paid-plan write (Levelcode::WebhookSync upgrading the
    # same row on a Stripe webhook) can't be clobbered by our free roll — without the lock
    # that read-decide-write is a TOCTOU lost update that silently downgrades a payer.
    def wallet_for(user)
      wallet = CreditWallet.find_or_initialize_by(user: user, product: PRODUCT)

      if wallet.new_record?
        roll_free!(wallet) # nothing to clobber; a lost INSERT race is caught below
        return wallet
      end

      wallet.with_lock do
        roll_free!(wallet) if !paid?(wallet) && needs_free_provision?(wallet)
      end
      wallet
    rescue ActiveRecord::RecordNotUnique
      # Lost the INSERT race to a concurrent provisioner (e.g. the paid-plan webhook) —
      # return the winner untouched rather than rolling it to free.
      CreditWallet.find_by!(user: user, product: PRODUCT)
    end

    # An ACTIVE paid plan — leave it alone. (Enforcement is the dollar budget now.)
    def paid?(wallet)
      key = wallet.plan_key.to_s
      key.present? && key != FREE_PLAN_KEY && wallet.budget_micros.to_i.positive?
    end

    # (Re)provision when the wallet isn't a valid free wallet yet: brand new / not
    # free / no period / month elapsed / budget somehow zeroed. Does NOT re-roll on a
    # mid-period value tweak, so usage isn't reset by an ENV change.
    def needs_free_provision?(wallet)
      wallet.plan_key.to_s != FREE_PLAN_KEY ||
        wallet.period_end.blank? ||
        wallet.period_end < Time.current ||
        wallet.budget_micros.to_i <= 0
    end

    def roll_free!(wallet)
      now = Time.current
      wallet.update!(
        plan_key: FREE_PLAN_KEY,
        input_cap: FREE_INPUT_CAP,
        output_cap: FREE_OUTPUT_CAP,
        # M14: the enforced ceiling is the DOLLAR budget (~$0.30/mo). Token caps stay as info.
        budget_micros: Levelcode.free_budget_micros,
        spent_micros: 0,
        # Hard cap → upgrade CTA (the M11 cost ceiling). The Redis hot counters key
        # on period_end, so a new period_end starts fresh counters automatically.
        overage_policy: "stop",
        period_start: now,
        period_end: now + 1.month,
        input_used: 0,
        output_used: 0
      )
    end

    private_class_method :paid?, :needs_free_provision?, :roll_free!
  end
end
