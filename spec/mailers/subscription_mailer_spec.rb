require "rails_helper"

RSpec.describe SubscriptionMailer, type: :mailer do
  let(:stripe_helper) { StripeMock.create_test_helper }
  before { StripeMock.start }
  after { StripeMock.stop }

  let(:user) { create(:user) }

  let(:invoice_data) do
    {
      plan_name: "Creator",
      amount_paid: "$9.99 USD",
      card_last4: "4242",
      period_end: "March 15, 2026",
      invoice_pdf: nil # Don't attempt real HTTP in tests
    }
  end

  describe "payment_failed" do
    let(:mail) { SubscriptionMailer.with(user: user).payment_failed }

    it "renders the headers" do
      expect(mail.subject).to eq("thin.ly - Payment Attempt Failed")
      expect(mail.to).to eq([ user.email ])
      expect(mail.from).to eq([ "notifications@thin.ly" ])
    end

    it "renders the body" do
      expect(mail.body.encoded).to match("Hi #{user.email},")
    end
  end

  describe "payment_completed" do
    let(:mail) { SubscriptionMailer.with(user: user, invoice_data: invoice_data).payment_completed }

    it "renders the headers" do
      expect(mail.subject).to eq("Welcome to thin.ly - Payment Confirmed")
      expect(mail.to).to eq([ user.email ])
      expect(mail.from).to eq([ "notifications@thin.ly" ])
    end

    it "renders the body with greeting" do
      expect(mail.body.encoded).to match("Hi #{user.email},")
    end

    it "includes plan details in the body" do
      body = mail.body.encoded
      expect(body).to include("Creator")
      expect(body).to include("$9.99 USD")
      expect(body).to include("March 15, 2026")
    end

    it "includes onboarding steps" do
      body = mail.body.encoded
      expect(body).to include("Shorten your first link")
      expect(body).to include("Generate a QR code")
    end

    context "without invoice_data" do
      let(:mail) { SubscriptionMailer.with(user: user).payment_completed }

      it "still sends the email without errors" do
        expect(mail.subject).to eq("Welcome to thin.ly - Payment Confirmed")
        expect(mail.body.encoded).to match("Hi #{user.email},")
      end
    end
  end

  describe "payment_successful" do
    let(:mail) { SubscriptionMailer.with(user: user, invoice_data: invoice_data).payment_successful }

    it "renders the headers" do
      expect(mail.subject).to eq("thin.ly - Payment Receipt - Thank You")
      expect(mail.to).to eq([ user.email ])
      expect(mail.from).to eq([ "notifications@thin.ly" ])
    end

    it "renders the body with greeting" do
      expect(mail.body.encoded).to match("Hi #{user.email},")
    end

    it "includes payment details in the body" do
      body = mail.body.encoded
      expect(body).to include("Creator")
      expect(body).to include("$9.99 USD")
      expect(body).to include("4242")
      expect(body).to include("March 15, 2026")
    end

    it "includes a link to the dashboard" do
      expect(mail.body.encoded).to include("/")
    end

    context "without invoice_data" do
      let(:mail) { SubscriptionMailer.with(user: user).payment_successful }

      it "still sends the email without errors" do
        expect(mail.subject).to eq("thin.ly - Payment Receipt - Thank You")
        expect(mail.body.encoded).to match("Hi #{user.email},")
      end
    end

    context "with an invoice_pdf URL" do
      let(:pdf_content) { "%PDF-1.4 fake pdf content" }
      let(:invoice_data_with_pdf) { invoice_data.merge(invoice_pdf: "https://pay.stripe.com/invoice/test/pdf") }
      let(:mail) { SubscriptionMailer.with(user: user, invoice_data: invoice_data_with_pdf).payment_successful }

      before do
        http_response = Net::HTTPSuccess.allocate
        allow(http_response).to receive(:body).and_return(pdf_content)

        http_double = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http_double)
        allow(http_double).to receive(:use_ssl=)
        allow(http_double).to receive(:open_timeout=)
        allow(http_double).to receive(:read_timeout=)
        allow(http_double).to receive(:request).and_return(http_response)
      end

      it "attaches a receipt.pdf file" do
        expect(mail.attachments.count).to eq(1)
        expect(mail.attachments.first.filename).to eq("receipt.pdf")
        expect(mail.attachments.first.mime_type).to eq("application/pdf")
      end
    end

    context "with a non-Stripe PDF URL" do
      let(:invoice_data_with_bad_url) { invoice_data.merge(invoice_pdf: "https://evil.com/malware.pdf") }
      let(:mail) { SubscriptionMailer.with(user: user, invoice_data: invoice_data_with_bad_url).payment_successful }

      it "does not attach a PDF and does not make an HTTP request" do
        expect(Net::HTTP).not_to receive(:new)
        expect(mail.attachments).to be_empty
      end
    end
  end

  describe "subscription_canceled" do
    let(:mail) { SubscriptionMailer.with(user: user).subscription_canceled }

    it "renders the headers" do
      expect(mail.subject).to eq("thin.ly - Subscription Canceled")
      expect(mail.to).to eq([ user.email ])
      expect(mail.from).to eq([ "notifications@thin.ly" ])
    end

    it "renders the body" do
      expect(mail.body.encoded).to match("Hi #{user.email},")
    end

    it "mentions the Free plan" do
      expect(mail.body.encoded).to include("Free plan")
    end
  end
end
