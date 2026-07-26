require "rails_helper"

RSpec.describe UserMailer, type: :mailer do
  describe "created" do
    let(:stripe_helper) { StripeMock.create_test_helper }
    before { StripeMock.start }
    after { StripeMock.stop }

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("NOTIFICATION_EMAIL").and_return("test@example.com")
      allow(ENV).to receive(:[]).with("LEVELCODE_MAIL_FROM").and_return(nil)
    end

    def attribution(source, handle)
      { "source" => source, "params" => { source => handle }, "landing" => "/ai" }
    end

    context "an organic signup" do
      let(:user) { create(:user) }
      let(:mail) { UserMailer.created(user) }

      it "renders LevelCode-branded headers" do
        expect(mail.subject).to eq("New LevelCode signup: #{user.email}")
        expect(mail.to).to eq([ "test@example.com" ])
      end

      it "says the signup was organic and carries no thin.ly branding" do
        body = mail.body.encoded
        expect(body).to match(user.email)
        expect(body).to match(/Organic/)
        expect(body).to match("levelcode.ai")
        expect(body).not_to match(/Smart URL Shortener/)
      end
    end

    context "a referred signup" do
      let(:user) { create(:user, signup_attribution: attribution("linkedin", "anastasia")) }
      let(:mail) { UserMailer.created(user) }

      it "names the channel and handle in the subject" do
        expect(mail.subject).to eq("New LevelCode signup via linkedin / anastasia: #{user.email}")
      end

      it "shows the referral in the body" do
        body = mail.body.encoded
        expect(body).to match("linkedin")
        expect(body).to match("anastasia")
        expect(body).not_to match(/Organic/)
      end
    end

    context "a channel with no handle" do
      let(:user) { create(:user, signup_attribution: { "source" => "linkedin", "params" => {} }) }

      it "falls back to the channel alone" do
        expect(UserMailer.created(user).subject).to eq("New LevelCode signup via linkedin: #{user.email}")
      end
    end

    context "sign-up method" do
      it "reports the OAuth provider when there is one" do
        user = create(:user, provider: "github", uid: "12345")
        expect(UserMailer.created(user).body.encoded).to match("GitHub")
      end

      it "reports Email otherwise" do
        expect(UserMailer.created(create(:user)).body.encoded).to match("Email")
      end
    end
  end
end
