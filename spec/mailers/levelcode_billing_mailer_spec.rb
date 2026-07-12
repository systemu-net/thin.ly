require "rails_helper"

RSpec.describe LevelcodeBillingMailer, type: :mailer do
  describe "#welcome" do
    let(:user) { double("user", email: "dev@example.com") }
    let(:plan) { Levelcode.plan("orbits_pro") } # real PLANS hash: name "Pro", $20/mo, ~260 turns
    let(:mail) do
      described_class.with(
        user: user, plan: plan, plan_key: "orbits_pro",
        period_end: Time.utc(2026, 8, 1).to_datetime
      ).welcome
    end

    it "sends to the buyer with a LevelCode-branded subject and from-address" do
      expect(mail.to).to eq([ "dev@example.com" ])
      expect(mail.subject).to eq("Welcome to LevelCode Cloud — your Pro plan is active")
      expect(mail[:from].to_s).to include("LevelCode") # display name, not thin.ly's default
    end

    it "is multipart (html + text)" do
      expect(mail.html_part).to be_present
      expect(mail.text_part).to be_present
    end

    context "the HTML part" do
      subject(:body) { mail.html_part.body.to_s }

      it "shows the plan, price, and renewal date" do
        expect(body).to include("LevelCode Cloud Pro")
        expect(body).to include("$20/mo")
        expect(body).to include("August 1, 2026")
      end

      it "gives the verified activation step (providerMode → gateway)" do
        expect(body).to include("levelcode.ai.providerMode")
        expect(body).to include("gateway")
      end

      it "links the account dashboard and carries no thin.ly chrome" do
        expect(body).to include("https://levelcode.ai/ai/account")
        expect(body).not_to match(/thin\.ly/i)
      end
    end

    it "renders a plain-text alternative with the same activation guidance" do
      text = mail.text_part.body.to_s
      expect(text).to include("SWITCH IT ON IN THE EDITOR")
      expect(text).to include("levelcode.ai.providerMode")
      expect(text).to include("https://levelcode.ai/ai/account")
    end

    it "renders gracefully when optional plan fields are missing" do
      m = described_class.with(user: user, plan: {}, plan_key: "orbits_pro", period_end: nil).welcome
      expect { m.html_part.body.to_s }.not_to raise_error
      expect(m.subject).to include("Cloud plan is active") # @plan_name defaults to "Cloud"
    end
  end
end
