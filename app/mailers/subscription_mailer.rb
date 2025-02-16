class SubscriptionMailer < ApplicationMailer
  default from: "notifications@thin.ly"
  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.subscription_mailer.payment_failed.subject
  #
  def payment_failed
    @user = params[:user]

    mail to: @user.email, subject: "Payment attempt failed"
  end

  def payment_completed
    @user = params[:user]

    mail to: @user.email, subject: "Payment completed"
  end

  def payment_successful
    @user = params[:user]

    mail to: @user.email, subject: "Payment successful"
  end
end
