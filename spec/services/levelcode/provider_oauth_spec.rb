require "rails_helper"

# The request specs stub ProviderOAuth.authorize_url, so the real client-id resolution isn't exercised
# there. This pins the Google-credential fallback that lets levelcode.ai reuse the already-configured
# GOOGLE_CLIENT_ID (only the client SECRET need be added to the env for the auth-code flow).
RSpec.describe Levelcode::ProviderOAuth do
  GOOGLE_ENV = %w[GOOGLE_OAUTH_ID GOOGLE_CLIENT_ID GOOGLE_OAUTH_SECRET GOOGLE_CLIENT_SECRET].freeze

  around do |example|
    saved = ENV.slice(*GOOGLE_ENV)
    GOOGLE_ENV.each { |k| ENV.delete(k) }
    example.run
  ensure
    GOOGLE_ENV.each { |k| ENV.delete(k) }
    saved.each { |k, v| ENV[k] = v }
  end

  def google_url
    described_class.authorize_url(provider: "google", redirect_uri: "https://levelcode.ai/ai/auth/callback", state: "s")
  end

  describe "Google authorize URL — client-id resolution" do
    it "uses GOOGLE_CLIENT_ID (the shared GIS client) when no dedicated GOOGLE_OAUTH_ID is set" do
      ENV["GOOGLE_CLIENT_ID"] = "shared-client.apps.googleusercontent.com"
      url = google_url
      expect(url).to start_with("https://accounts.google.com/o/oauth2/v2/auth")
      expect(url).to include("client_id=shared-client.apps.googleusercontent.com")
    end

    it "prefers a dedicated GOOGLE_OAUTH_ID when both are set" do
      ENV["GOOGLE_CLIENT_ID"] = "shared"
      ENV["GOOGLE_OAUTH_ID"] = "dedicated"
      expect(google_url).to include("client_id=dedicated")
    end

    it "carries the auth-code flow params the LevelCode editor handoff needs" do
      ENV["GOOGLE_CLIENT_ID"] = "shared"
      url = described_class.authorize_url(
        provider: "google", redirect_uri: "https://levelcode.ai/ai/auth/callback", state: "st8", code_challenge: "chal"
      )
      expect(url).to include("response_type=code")
      expect(url).to include("state=st8")
      expect(url).to include("code_challenge=chal", "code_challenge_method=S256")
      expect(url).to include(CGI.escape("https://levelcode.ai/ai/auth/callback"))
    end
  end

  # The outage this file previously could not have caught.
  #
  # Everything above tests the URL we send the browser TO. Nothing tested what happens when it
  # comes BACK, so a Google sign-in that never produced a user still passed the whole suite.
  # These start one step later — at a verified id_token payload — and assert the only outcome
  # that matters: a person who has never signed in before ends up with an account.
  describe "signing in a brand-new person" do
    let(:payload) do
      { "sub" => "google-uid-1", "email" => "brand-new@example.com", "email_verified" => true }
    end

    # Stub only the two steps that leave the process — the token exchange and Google's signature
    # check — so the assertions run through the REAL google_user, including the terms flag and
    # the logging seam. Stubbing User.from_google instead would test nothing: that is precisely
    # the call whose arguments were wrong.
    def sign_in_with_google
      allow(described_class).to receive(:google_exchange_code).and_return("id.token.stub")
      allow(described_class).to receive(:verify_google_id_token).and_return(payload)
      described_class.google_user(code: "auth-code", redirect_uri: "https://levelcode.ai/ai/auth/callback")
    end

    before { allow(Stripe::Customer).to receive(:create).and_return(double(id: "cus_spec")) }

    it "GOOGLE creates the account (regression: every new signup was rejected)" do
      user = sign_in_with_google

      expect(user.persisted?).to be(true),
        "new Google signup rejected: #{user.errors.full_messages.inspect}"
      expect(user.email).to eq("brand-new@example.com")
      expect(user.provider).to eq(User::GOOGLE_PROVIDER)
    end

    it "records the acceptance shown on /ai/login, rather than merely passing validation" do
      # `acceptance:` validators are satisfied by a virtual attribute, so "it saved" is not proof
      # the acceptance was actually written down. The audit trail is the point.
      user = sign_in_with_google

      expect(user.terms_accepted).to be(true)
      expect(user.terms_accepted_at).to be_present
      expect(user.terms_accepted_version).to eq(User::TERMS_VERSION)
    end

    it "GITHUB creates the account too — the control that stayed green throughout" do
      user = described_class.send(:find_or_create_oauth_user,
                                  provider: "github", uid: "gh-1", email: "gh-new@example.com")

      expect(user.persisted?).to be(true), user.errors.full_messages.inspect
      expect(user.terms_accepted_at).to be_present
    end

    it "an EXISTING person signs in unchanged — the asymmetry that hid the outage" do
      # Validation is `on: :create`, so returning users never hit it. Chrome, Firefox and mobile
      # all "worked" for anyone with an account, which is why this looked like a browser bug.
      existing = User.create!(provider: User::GOOGLE_PROVIDER, uid: "google-uid-1",
                              email: "brand-new@example.com", password: "password123",
                              terms_accepted: true)

      expect(sign_in_with_google.id).to eq(existing.id)
    end

    it "names the failing attribute in the log instead of failing silently" do
      # The outage was invisible because a validation rejection and a provider outage produced
      # the identical `?error=oauth_failed`. Anything that stops a signup must say so.
      allow(Rails.logger).to receive(:error)
      allow(User).to receive(:from_google).and_return(User.new.tap(&:validate))

      sign_in_with_google

      expect(Rails.logger).to have_received(:error).with(/google sign-up rejected by validation/i)
    end
  end
  # Until this was added, perform_http set NO timeouts, so every provider call inherited Net::HTTP's
  # 60-second defaults. A Google sign-in makes two of them back to back, so one stalled provider held
  # the browser on a blank spinner for ~2 minutes before the callback gave up. Reported by customers as
  # "sign-in is stuck loading".
  describe "outbound provider HTTP is bounded" do
    # perform_http is private and every provider call funnels through it, so pinning it here covers the
    # Google token exchange, the id_token key fetch, and both GitHub calls at once.
    def perform(http_double)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      described_class.send(:perform_http, URI.parse("https://oauth2.googleapis.com/token"), double("req"))
    end

    it "sets a connect, read AND write timeout on every call" do
      http = double("http")
      allow(http).to receive(:request).and_return(double("res"))
      expect(http).to receive(:open_timeout=).with(described_class::OPEN_TIMEOUT)
      expect(http).to receive(:read_timeout=).with(described_class::READ_TIMEOUT)
      expect(http).to receive(:write_timeout=).with(described_class::WRITE_TIMEOUT)
      perform(http)
    end

    it "keeps the timeouts short enough that a stalled provider cannot outlast a user's patience" do
      # The failure mode being prevented is a spinner with no end, so the bound that matters is the
      # WORST CASE for one sign-in: two sequential calls, each able to burn connect + read.
      worst_case = 2 * (described_class::OPEN_TIMEOUT + described_class::READ_TIMEOUT)
      expect(worst_case).to be <= 40
      expect(described_class::OPEN_TIMEOUT).to be >= 2   # not so tight that a slow TLS handshake fails
    end

    it "turns a timeout into nil rather than an exception, so the callback can show an error" do
      # perform_http returning nil is what makes oauth_callback redirect to /ai/login?error=oauth_failed.
      # If a timeout escaped instead, the user would get a 500 — still broken, but now unexplained.
      http = double("http")
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:write_timeout=)
      allow(http).to receive(:request).and_raise(Net::ReadTimeout)
      allow(Net::HTTP).to receive(:new).and_return(http)

      expect {
        expect(described_class.send(:perform_http, URI.parse("https://oauth2.googleapis.com/token"), double("req"))).to be_nil
      }.not_to raise_error
    end
  end

end
