# frozen_string_literal: true

require "rails_helper"

# Passwordless email + one-time-code sign-in (Levelcode::EmailCode). Redis/mailer are
# stubbed so the spec is hermetic; the OTP store itself is unit-tested separately.
RSpec.describe "Api::Levelcode::V1 email OTP auth", type: :request do
  let(:svc) { "test-service-token" }
  let(:svc_headers) { { "X-Levelcode-Service-Token" => svc } }

  before do
    ENV["LEVELCODE_JWT_SECRET"] = "test-secret"
    ENV["LEVELCODE_SITE_SERVICE_TOKEN"] = svc
    # Verifying an OTP creates the user through the controller (not the factory),
    # so the real create_stripe_customer callback fires — stub Stripe to stay hermetic.
    allow(Stripe::Customer).to receive(:create).and_return(Stripe::Customer.construct_from(id: "cus_test"))
    allow(Stripe::Customer).to receive(:retrieve).and_return(Stripe::Customer.construct_from(id: "cus_test"))
  end

  after do
    ENV.delete("LEVELCODE_SITE_SERVICE_TOKEN")
    ENV.delete("LEVELCODE_JWT_SECRET")
  end

  def json
    response.parsed_body
  end

  describe "POST /api/levelcode/v1/auth/email/request" do
    it "rejects a missing service token (403)" do
      post "/api/levelcode/v1/auth/email/request", params: { email: "a@b.com" }
      expect(response).to have_http_status(:forbidden)
    end

    it "422s an invalid email" do
      post "/api/levelcode/v1/auth/email/request", params: { email: "not-an-email" }, headers: svc_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("invalid_email")
    end

    it "issues a code and emails it (email normalized)" do
      mail = instance_double(ActionMailer::MessageDelivery, deliver_now: true)
      allow(Levelcode::EmailCode).to receive(:issue).with("user@example.com").and_return("123456")
      allow(LevelcodeAuthMailer).to receive(:login_code).with("user@example.com", "123456").and_return(mail)

      post "/api/levelcode/v1/auth/email/request", params: { email: "User@Example.com" }, headers: svc_headers

      expect(response).to have_http_status(:ok)
      expect(json["sent"]).to be(true)
      expect(LevelcodeAuthMailer).to have_received(:login_code).with("user@example.com", "123456")
    end

    it "still 200s (sent:true) when the resend is throttled" do
      allow(Levelcode::EmailCode).to receive(:issue).and_raise(Levelcode::EmailCode::RateLimited)
      post "/api/levelcode/v1/auth/email/request", params: { email: "u@e.com" }, headers: svc_headers
      expect(response).to have_http_status(:ok)
      expect(json["sent"]).to be(true)
    end
  end

  describe "POST /api/levelcode/v1/auth/email/verify" do
    it "rejects an invalid / expired code (401)" do
      allow(Levelcode::EmailCode).to receive(:verify).and_return(false)
      post "/api/levelcode/v1/auth/email/verify", params: { email: "u@e.com", code: "000000" }, headers: svc_headers
      expect(response).to have_http_status(:unauthorized)
      expect(json.dig("error", "code")).to eq("invalid_code")
    end

    context "with a valid code" do
      before { allow(Levelcode::EmailCode).to receive(:verify).and_return(true) }

      it "web mode: creates the user and returns a web SESSION + profile (never the gateway access token)" do
        expect {
          post "/api/levelcode/v1/auth/email/verify",
               params: { email: "new@example.com", code: "123456", mode: "web" }, headers: svc_headers
        }.to change(User, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(json["session"]).to be_present
        # Security: the web cookie session must NOT carry the editor's ai:* access token.
        expect(json["access"]).to be_nil
        expect(json.dig("profile", "email")).to eq("new@example.com")
      end

      it "editor mode: returns a one-time code, not tokens" do
        allow(Levelcode::OneTimeCode).to receive(:issue).and_return("one-time")
        post "/api/levelcode/v1/auth/email/verify",
             params: { email: "e@example.com", code: "123456", mode: "editor" }, headers: svc_headers

        expect(response).to have_http_status(:ok)
        expect(json["code"]).to eq("one-time")
        expect(json["access"]).to be_nil
      end

      it "reuses an existing user (no duplicate)" do
        User.create!(email: "existing@example.com", password: "password123", terms_accepted: true)
        expect {
          post "/api/levelcode/v1/auth/email/verify",
               params: { email: "existing@example.com", code: "123456", mode: "web" }, headers: svc_headers
        }.not_to change(User, :count)
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
