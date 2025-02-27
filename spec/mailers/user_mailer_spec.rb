require "rails_helper"

RSpec.describe UserMailer, type: :mailer do
  describe "created" do
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
