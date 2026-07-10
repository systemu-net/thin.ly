# frozen_string_literal: true

# Create/refresh the Stripe Prices the LevelCode checkout + webhook depend on.
#
# WHY: Levelcode::WebController#checkout finds a Stripe Price by its lookup_key
# (= plan[:stripe_lookup_key]); Levelcode::WebhookSync reads that SAME lookup_key off
# the subscription to provision the wallet (plan/caps/budget). So every plan in
# Levelcode::PLANS needs a recurring monthly Stripe Price whose lookup_key matches —
# without it, the editor shows "That plan is unavailable." and no purchase can start.
#
# This task reads straight from Levelcode::PLANS (the single source of truth), so it can
# never drift from the app. It runs against whatever Stripe account + MODE the app's
# STRIPE_SECRET_KEY points at (Stripe.api_key) — sk_test_* → TEST, sk_live_* → LIVE.
#
# Idempotent: Stripe Prices are immutable, so re-running creates a NEW price and
# transfer_lookup_key moves the lookup_key onto it — checkout/webhook always resolve the
# newest. Safe to re-run any time (e.g. after a price change), and again in LIVE mode.
#
#   bin/rails levelcode:stripe:sync_prices                # currency defaults to usd
#   bin/rails levelcode:stripe:sync_prices CURRENCY=eur
namespace :levelcode do
  namespace :stripe do
    desc "Create/refresh a recurring Stripe Price for every Levelcode plan (matches PLANS lookup_keys)"
    task sync_prices: :environment do
      currency = (ENV["CURRENCY"].presence || "usd").downcase
      mode = Stripe.api_key.to_s.start_with?("sk_live") ? "LIVE" : "TEST"
      puts "Stripe #{mode} mode · currency #{currency.upcase}"

      Levelcode::PLANS.each do |plan|
        price = Stripe::Price.create(
          unit_amount: plan[:price_cents],
          currency: currency,
          recurring: { interval: plan[:interval] },
          product_data: { name: "LevelCode #{plan[:name]}" },
          lookup_key: plan[:stripe_lookup_key],
          transfer_lookup_key: true
        )
        puts format("  ok  %-16s $%d/%s  ->  %s", plan[:stripe_lookup_key], plan[:price_cents] / 100, plan[:interval], price.id)
      end

      puts "Done. Verify in Stripe Dashboard → Product catalog (#{mode} mode): 4 prices with lookup keys " \
           "#{Levelcode::PLANS.map { |p| p[:stripe_lookup_key] }.join(', ')}."
    end
  end
end
