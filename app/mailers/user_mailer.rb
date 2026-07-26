# frozen_string_literal: true

# Internal ops notification: a new account was created.
#
# Branded LevelCode and rendered without ApplicationMailer's thin.ly "mailer"
# layout, following LevelcodeAuthMailer / LevelcodeBillingMailer — the template is
# self-contained so it cannot inherit a link-shortener header and footer.
class UserMailer < ApplicationMailer
  layout false

  def created(user)
    @user = user
    @email = user.email
    @created_at = user.created_at
    @signup_method = signup_method_for(user)

    # The point of the referral work: say in the notification itself which
    # channel produced this signup. nil for an organic one.
    @attribution = user.signup_attribution.presence
    @channel = @attribution&.dig("source").presence
    @handle = referral_handle(@attribution)
    @landing = @attribution&.dig("landing").presence

    mail(
      to: ENV["NOTIFICATION_EMAIL"] || Rails.application.credentials.notification_email,
      from: ENV["LEVELCODE_MAIL_FROM"].presence || "LevelCode <notifications@thin.ly>",
      subject: subject_for(@email, @channel, @handle)
    )
  end

  private

  # Channel in the subject line, so a run of these is scannable from the inbox
  # list without opening anything.
  #
  # Every interpolated value is scrubbed of control characters first. The
  # sanitizer now strips them before storing, but rows written BEFORE that fix
  # are still in the table, and a CR/LF in a mail header is injection — which the
  # Mail gem answers by raising, taking the notification job down with it. A
  # header builder should not trust its inputs regardless of who cleaned them
  # upstream.
  def subject_for(email, channel, handle)
    email = header_safe(email)
    channel = header_safe(channel)
    handle = header_safe(handle)

    return "New LevelCode signup: #{email}" if channel.blank?

    via = handle.present? ? "#{channel} / #{handle}" : channel
    "New LevelCode signup via #{via}: #{email}"
  end

  def header_safe(value)
    value.to_s.gsub(/[[:cntrl:]]/, " ").squeeze(" ").strip
  end

  # How they got in. `provider` is set only on the OAuth paths.
  #
  # Compared against the constants, not literals: Google's stored value is
  # "google_oauth2" (User::GOOGLE_PROVIDER), so a hardcoded "google" silently
  # falls through and reports every Google signup as Email.
  def signup_method_for(user)
    case user.provider.to_s
    when ::Levelcode::ProviderOAuth::GITHUB_PROVIDER then "GitHub"
    when User::GOOGLE_PROVIDER then "Google"
    else "Email"
    end
  end

  # The partner handle behind the channel: the params value named by `source`
  # (source "linkedin" -> params["linkedin"]). Falls back to `ref`, which is where
  # a raw ref campaign lands.
  def referral_handle(attribution)
    return nil if attribution.blank?

    params = attribution["params"]
    return nil unless params.is_a?(Hash)

    params[attribution["source"].to_s].presence || params["ref"].presence
  end
end
