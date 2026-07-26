# Preview all emails at http://localhost:3000/rails/mailers/user_mailer
#
# Both variants are previewable because the referral block is the part worth
# eyeballing — and it is the branch you only see when a campaign link was used.
# Users are built, never saved, so opening a preview cannot create accounts or
# fire the signup notification.
class UserMailerPreview < ActionMailer::Preview
  # http://localhost:3000/rails/mailers/user_mailer/created
  def created
    UserMailer.created(sample_user)
  end

  # http://localhost:3000/rails/mailers/user_mailer/created_via_referral
  def created_via_referral
    UserMailer.created(
      sample_user(
        provider: "github",
        signup_attribution: {
          "source" => "linkedin",
          "params" => { "linkedin" => "saienkoanastasia" },
          "landing" => "/ai",
          "recorded_at" => Time.current.utc.iso8601
        }
      )
    )
  end

  private

  def sample_user(**attrs)
    User.new({ id: 1234, email: "new.user@example.com", created_at: Time.current }.merge(attrs))
  end
end
