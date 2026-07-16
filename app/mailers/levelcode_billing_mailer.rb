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

  # Sent when an existing subscriber moves between paid plans.
  #   upgrade   — enqueued best-effort from Levelcode::WebhookSync, which observes the immediate flip.
  #   downgrade — enqueued best-effort from Levelcode::PlanChange when the change is SCHEDULED, since the
  #               switch itself is deferred to period end and the webhook only sees it a month later.
  #
  # Params (via .with): user:, from_plan: (old PLANS hash), plan: (new PLANS hash), plan_key:,
  #   direction: "upgrade" | "downgrade", period_end: (DateTime — the current period's end).
  def plan_changed
    @user        = params[:user]
    @direction   = params[:direction].to_s
    @downgrade   = @direction == "downgrade"
    @from_name   = plan_name(params[:from_plan])
    @plan        = params[:plan] || {}
    @plan_name   = plan_name(@plan)
    @price       = format_price(@plan[:price_cents])
    @turns       = @plan[:turns]
    # A downgrade is deferred to the period boundary by a Stripe subscription schedule, so this date is BOTH
    # when the new rate starts AND when the current (higher) plan's limits stop — the customer keeps the
    # tier they already paid for until then. Upgrades are immediate/prorated, so it's just the renewal date.
    @effective_on = params[:period_end]&.strftime("%B %-d, %Y")
    @account_url = "#{LEVELCODE_SITE}/ai/account"

    subject =
      if @downgrade
        "Your LevelCode Cloud plan will change to #{@plan_name}"
      else
        "You're now on LevelCode Cloud #{@plan_name}"
      end

    mail(to: @user.email, from: LEVELCODE_FROM, subject: subject)
  end

  # Sent when a paid subscription is canceled / reverts to the free tier — enqueued best-effort
  # from Levelcode::WebhookSync#teardown (customer.subscription.deleted).
  #
  # Params (via .with): user:, plan: (the canceled PLANS hash), plan_key:, ends_on: (DateTime|nil).
  def canceled
    @user        = params[:user]
    @from_name   = plan_name(params[:plan])
    @ends_on     = params[:ends_on]&.strftime("%B %-d, %Y")
    @account_url = "#{LEVELCODE_SITE}/ai/account"
    @pricing_url = "#{LEVELCODE_SITE}/ai/pricing"

    mail(
      to: @user.email,
      from: LEVELCODE_FROM,
      subject: "Your LevelCode Cloud #{@from_name} plan has been canceled"
    )
  end

  private

  def plan_name(plan)
    (plan && plan[:name]).presence || "Cloud"
  end

  def format_price(cents)
    return nil if cents.blank?

    "$#{cents.to_i / 100}/mo"
  end
end
