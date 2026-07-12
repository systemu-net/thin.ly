# frozen_string_literal: true

# LevelCode Cloud transactional (billing) email. Kept separate from SubscriptionMailer — the link
# shortener's mailer — so its branding and from-address are LevelCode's, not thin.ly's. Renders
# WITHOUT the shared thin.ly `mailer` layout (`layout false`); the templates are fully self-contained
# and inline-styled, so no thin.ly chrome leaks into a LevelCode email. Mirrors LevelcodeAuthMailer.
class LevelcodeBillingMailer < ApplicationMailer
  layout false

  # The one Rails host serves the account SPA under /ai (see StaticController::LEVELCODE_HOSTS).
  LEVELCODE_SITE = "https://levelcode.ai"

  # LevelCode-branded sender, overriding the thin.ly default. Point LEVELCODE_MAIL_FROM at a verified
  # levelcode.ai address once the domain is set up (same knob LevelcodeAuthMailer uses).
  LEVELCODE_FROM = (ENV["LEVELCODE_MAIL_FROM"].presence || "LevelCode <notifications@thin.ly>").freeze

  # Sent ONCE, on a user's first paid LevelCode Cloud purchase — enqueued best-effort from
  # Levelcode::WebhookSync#provision_from_stripe_subscription. Plan-centric (no invoice PDF), so the
  # money-critical webhook path adds no extra Stripe API calls.
  #
  # Params (via .with): user:, plan: (a Levelcode::PLANS hash), plan_key:, period_end: (DateTime).
  def welcome
    @user        = params[:user]
    @plan        = params[:plan] || {}
    @plan_name   = @plan[:name].presence || "Cloud"
    @price       = format_price(@plan[:price_cents])
    @turns       = @plan[:turns]
    @renews_on   = params[:period_end]&.strftime("%B %-d, %Y")
    @account_url = "#{LEVELCODE_SITE}/ai/account"
    @pricing_url = "#{LEVELCODE_SITE}/ai/pricing"
    @download_url = LEVELCODE_SITE
    @provider_setting = "levelcode.ai.providerMode"

    mail(
      to: @user.email,
      from: LEVELCODE_FROM,
      subject: "Welcome to LevelCode Cloud — your #{@plan_name} plan is active"
    )
  end

  private

  def format_price(cents)
    return nil if cents.blank?

    "$#{cents.to_i / 100}/mo"
  end
end
