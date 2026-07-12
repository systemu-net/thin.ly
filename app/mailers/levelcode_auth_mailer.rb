# frozen_string_literal: true

# LevelCode Cloud passwordless sign-in email. Kept separate from the link-shortener
# mailers so its branding/from-address are independent (Levelcode::EmailCode).
class LevelcodeAuthMailer < ApplicationMailer
  # Render without ApplicationMailer's thin.ly-branded "mailer" layout: the
  # LevelCode templates are fully self-contained (own LevelCode wordmark + inline
  # styles), so inheriting that layout would wrap a LevelCode email in a thin.ly
  # header/footer. Mirrors the self-contained approach used by the LevelCode
  # billing mailer.
  layout false

  def login_code(email, code)
    @code = code
    @ttl_minutes = (Levelcode::EmailCode::TTL / 60).to_i
    mail(
      to: email,
      from: ENV["LEVELCODE_MAIL_FROM"].presence || "LevelCode <notifications@thin.ly>",
      subject: "#{code} is your LevelCode sign-in code"
    )
  end
end
