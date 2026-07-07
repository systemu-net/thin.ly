# frozen_string_literal: true

# LevelCode Cloud passwordless sign-in email. Kept separate from the link-shortener
# mailers so its branding/from-address are independent (Levelcode::EmailCode).
class LevelcodeAuthMailer < ApplicationMailer
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
