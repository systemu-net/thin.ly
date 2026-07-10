# frozen_string_literal: true

module Levelcode
  # Per-call Stripe credentials for the ISOLATED LevelCode Stripe account.
  #
  # LevelCode billing runs on its OWN Stripe account (separate from the linkly URL
  # shortener), so its invoices/receipts/portal/emails carry the LevelCode brand and
  # its webhook events never collide with linkly's. The global `Stripe.api_key`
  # (config/initializers/stripe.rb) stays the LINKLY account; every LevelCode Stripe
  # call passes `Billing.opts` as the trailing per-request opts arg so it runs under
  # the LevelCode key. No global mutation → thread-safe. The api_version pin on the
  # global config still applies (per-call opts inherit it).
  #
  # NOTE: this module is deliberately named Billing, NOT Stripe — a `Levelcode::Stripe`
  # would shadow the top-level ::Stripe gem constant inside `module Levelcode` code
  # (webhook_sync.rb, web_controller.rb write bare `Stripe::…`) and break every call.
  module Billing
    module_function

    def key
      ENV["LEVELCODE_STRIPE_SECRET_KEY"].presence ||
        Rails.application.credentials.dig(:levelcode_stripe_secret_key)
    end

    # Trailing opts hash for a Stripe call → routes it to the LevelCode account.
    #   Stripe::Price.list({ lookup_keys: [key] }, Levelcode::Billing.opts)
    # IMPORTANT: the CALL's own params must be their own explicit hash — appending
    # this to bare keyword args merges it in and Stripe silently ignores api_key.
    def opts
      { api_key: key }
    end

    def webhook_secret
      ENV["LEVELCODE_STRIPE_WEBHOOK_SIGNING_SECRET"].presence ||
        Rails.application.credentials.dig(:levelcode_stripe_webhook_signing_secret)
    end
  end
end
