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

  describe "#plan_changed" do
    let(:user) { double("user", email: "dev@example.com") }
    let(:pro) { Levelcode.plan("orbits_pro") }        # $20
    let(:pro_plus) { Levelcode.plan("orbits_pro_plus") } # $40

    it "upgrade: immediate/prorated framing, both plan names, LevelCode-branded" do
      mail = described_class.with(
        user: user, from_plan: pro, plan: pro_plus, plan_key: "orbits_pro_plus",
        direction: "upgrade", period_end: Time.utc(2026, 8, 1).to_datetime
      ).plan_changed

      expect(mail.to).to eq([ "dev@example.com" ])
      expect(mail.subject).to eq("You're now on LevelCode Cloud Pro+")
      expect(mail[:from].to_s).to include("LevelCode")
      body = mail.html_part.body.to_s
      expect(body).to include("Pro")      # from
      expect(body).to include("Pro+")     # to
      expect(body).to include("$40/mo")
      expect(body).to match(/right away|prorated/i)
      expect(body).not_to match(/thin\.ly/i)
    end

    it "downgrade: period-end framing with the effective date" do
      mail = described_class.with(
        user: user, from_plan: pro_plus, plan: pro, plan_key: "orbits_pro",
        direction: "downgrade", period_end: Time.utc(2026, 8, 1).to_datetime
      ).plan_changed

      expect(mail.subject).to eq("Your LevelCode Cloud plan will change to Pro")
      expect(mail.html_part.body.to_s).to match(/next billing period/i)
      expect(mail.html_part.body.to_s).to include("August 1, 2026")
      expect(mail.text_part.body.to_s).to match(/next billing period/i)
    end
  end

  describe "#canceled" do
    let(:user) { double("user", email: "dev@example.com") }
    let(:mail) do
      described_class.with(
        user: user, plan: Levelcode.plan("orbits_pro_plus"), plan_key: "orbits_pro_plus",
        ends_on: Time.utc(2026, 8, 1).to_datetime
      ).canceled
    end

    it "names the canceled plan, points to free tier + resubscribe, LevelCode-branded" do
      expect(mail.to).to eq([ "dev@example.com" ])
      expect(mail.subject).to eq("Your LevelCode Cloud Pro+ plan has been canceled")
      expect(mail[:from].to_s).to include("LevelCode")
      body = mail.html_part.body.to_s
      expect(body).to include("Pro+")
      expect(body).to match(/free tier/i)
      expect(body).to include("https://levelcode.ai/ai/pricing")
      expect(body).not_to match(/thin\.ly/i)
    end
  end
end
