class UserMailer < ApplicationMailer
  def created(user)
    @created_user_email = user.email

    mail to: ENV["NOTIFICATION_EMAIL"], subject: "New user created"
  end
end
