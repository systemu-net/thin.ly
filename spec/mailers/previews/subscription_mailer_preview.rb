# Preview all emails at http://localhost:3000/rails/mailers/subscription_mailer
class SubscriptionMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/subscription_mailer/payment_failed
  def payment_failed
    SubscriptionMailer.with(user: User.first).payment_failed
  end
end
