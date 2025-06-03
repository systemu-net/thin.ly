require "rails_helper"

RSpec.describe SubscriptionMailer, type: :mailer do
  let(:stripe_helper) { StripeMock.create_test_helper }
  before { StripeMock.start }
  after { StripeMock.stop }

  describe "payment_failed" do
    let(:mail) { SubscriptionMailer.with(user: user).payment_failed }
    let(:user) { create(:user) }

    it "renders the headers" do
      expect(mail.subject).to eq("Payment attempt failed")
      expect(mail.to).to eq([ user.email ])
      expect(mail.from).to eq([ "notifications@thin.ly" ])
    end

    it "renders the body" do
      expect(mail.body.encoded).to match("Hi #{user.email},")
    end
  end

  describe "payment_completed" do
    let(:mail) { SubscriptionMailer.with(user: user).payment_completed }
    let(:user) { create(:user) }

    it "renders the headers" do
      expect(mail.subject).to eq("Payment completed")
      expect(mail.to).to eq([ user.email ])
      expect(mail.from).to eq([ "notifications@thin.ly" ])
    end

    it "renders the body" do
      expect(mail.body.encoded).to match("Hi #{user.email},")
    end
  end

  describe "payment_successful" do
    let(:mail) { SubscriptionMailer.with(user: user).payment_successful }
    let(:user) { create(:user) }

    it "renders the headers" do
      expect(mail.subject).to eq("Payment successful")
      expect(mail.to).to eq([ user.email ])
      expect(mail.from).to eq([ "notifications@thin.ly" ])
    end

    it "renders the body" do
      expect(mail.body.encoded).to match("Hi #{user.email},")
    end
  end
end
