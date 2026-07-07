# frozen_string_literal: true

# Shared geo + access/auth capture for the admin dashboard. Country comes from the CDN edge
# header (Cloudflare / CloudFront) — the same source the shortener uses; nil in dev (no CDN).
# Everything here is best-effort: it must never break the request it's attached to.
module AccessTracking
  extend ActiveSupport::Concern

  # Two-letter country from the CDN edge; nil when not behind a CDN (local/dev).
  def request_country
    (request.headers["CF-IPCountry"].presence ||
     request.headers["CloudFront-Viewer-Country"].presence).to_s.strip.upcase.presence
  end

  # Denormalize "last seen where/when" onto the user, THROTTLED to ~once / 15 min so it's a rare
  # write instead of one per request. update_columns → no callbacks / validations / updated_at churn.
  def touch_access!(user)
    return unless user

    now = Time.current
    return if user.last_seen_at.present? && user.last_seen_at > now - 15.minutes

    attrs = { last_seen_at: now }
    country = request_country
    attrs[:last_country] = country if country.present?
    user.update_columns(attrs)
  rescue StandardError => e
    Rails.logger.warn("[AccessTracking] touch failed: #{e.class}: #{e.message}")
  end

  # Record one authentication attempt (success or failure) for the admin auth-health view.
  def log_auth(kind:, outcome:, email: nil, user: nil, provider: nil, reason: nil)
    AuthEvent.create!(
      user: user,
      email: (email || user&.email).to_s.strip.downcase.presence,
      kind: kind.to_s,
      provider: provider.presence,
      outcome: outcome.to_s,
      reason: reason.presence,
      ip: request.remote_ip,
      country: request_country,
      created_at: Time.current
    )
  rescue StandardError => e
    Rails.logger.warn("[AccessTracking] auth log failed: #{e.class}: #{e.message}")
  end
end
