require "rails_helper"

RSpec.describe LevelcodeAuthMailer, type: :mailer do
  describe "login_code" do
    let(:code) { "123456" }
    let(:mail) { described_class.login_code("user@example.com", code) }

    it "renders the headers" do
      expect(mail.subject).to eq("#{code} is your LevelCode sign-in code")
      expect(mail.to).to eq([ "user@example.com" ])
    end

    it "renders a self-contained, LevelCode-branded body" do
      expect(mail.body.encoded).to match("LevelCode")
      expect(mail.body.encoded).to include(code)
    end

    # Regression: LevelcodeAuthMailer sets `layout false` so a LevelCode email is
    # never wrapped in ApplicationMailer's thin.ly-branded "mailer" layout
    # (thin.ly wordmark header + "© <year> thin.ly" footer with thin.ly links).
    it "does not wrap the email in the thin.ly mailer layout" do
      expect(mail.body.encoded).not_to match(/thin\.ly/i)
    end
  end
end
