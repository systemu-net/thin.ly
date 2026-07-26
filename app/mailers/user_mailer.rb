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
  def subject_for(email, channel, handle)
    return "New LevelCode signup: #{email}" if channel.blank?

    via = handle.present? ? "#{channel} / #{handle}" : channel
    "New LevelCode signup via #{via}: #{email}"
  end

  # How they got in. `provider` is set only on the OAuth paths.
  def signup_method_for(user)
    case user.provider.to_s
    when "github" then "GitHub"
    when "google" then "Google"
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
