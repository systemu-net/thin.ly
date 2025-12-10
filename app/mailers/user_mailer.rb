class UserMailer < ApplicationMailer
  def created(user)
    @created_user_email = user.email

    mail to: ENV["NOTIFICATION_EMAIL"] || Rails.application.credentials.notification_email, subject: "New user created"
  end
end
