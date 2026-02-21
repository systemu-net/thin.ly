require "rails_helper"

RSpec.describe UserMailer, type: :mailer do
  describe "created" do
    let(:stripe_helper) { StripeMock.create_test_helper }
    before { StripeMock.start }
    after { StripeMock.stop }

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("NOTIFICATION_EMAIL").and_return("test@example.com")
    end

    let(:user) { create(:user) }
    let(:mail) { UserMailer.created(user) }

    it "renders the headers" do
      expect(mail.subject).to eq("New user created")
      expect(mail.to).to eq([ ENV["NOTIFICATION_EMAIL"] ])
      expect(mail.from).to eq([ "notifications@thin.ly" ])
    end

    it "renders the body" do
      expect(mail.body.encoded).to match("Welcome new user: #{user.email}")
    end
  end
end
