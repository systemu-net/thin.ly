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

  # perform_http carries the GitHub token exchange and API reads, and the Google token exchange.
  # (Google's signing keys are fetched by the googleauth gem itself, not through here.) These run it
  # against a real local socket rather than a double, so they describe what a provider would see and
  # hold however the Net::HTTP call happens to be written.
  describe "talking to a provider" do
    # A local stand-in for a provider. Given a response it answers each request with it; given none
    # it accepts the connection and never answers — the failure the timeouts exist for.
    def with_provider(response = nil)
      server = TCPServer.new("127.0.0.1", 0)
      connections = []
      listener = Thread.new do
        loop do
          socket = server.accept
          connections << socket
          next unless response

          socket.gets("\r\n\r\n") # the request head — the answered examples send no body
          socket.write(response)
          socket.close
        end
      end
      yield URI("http://127.0.0.1:#{server.addr[1]}/token"), connections
    ensure
      listener&.kill
      connections&.each { |socket| socket.close unless socket.closed? }
      server&.close
    end

    def http_response(status, body)
      "HTTP/1.1 #{status}\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
    end

    def perform(uri, request)
      described_class.send(:perform_http, uri, request)
    end

    # A stall should cost the suite a fraction of a second, not the ten a real sign-in is allowed.
    def with_read_timeout(seconds)
      stub_const("#{described_class}::HTTP_OPTIONS", described_class::HTTP_OPTIONS.merge(read_timeout: seconds))
    end

    it "returns the body of a successful response" do
      with_provider(http_response("200 OK", '{"access_token":"t"}')) do |uri|
        expect(perform(uri, Net::HTTP::Get.new(uri))).to eq('{"access_token":"t"}')
      end
    end

    it "returns nil for any other status, so the caller can fail the sign-in" do
      with_provider(http_response("503 Service Unavailable", "busy")) do |uri|
        expect(perform(uri, Net::HTTP::Get.new(uri))).to be_nil
      end
    end

    # nil rather than an exception is what sends the callback to /ai/login?error=oauth_failed — an
    # error the user can retry — instead of a 500. The clock is what proves the timeout was applied:
    # without one, this still returns nil, after Net::HTTP's default sixty seconds.
    it "gives up on a provider that accepts the connection and never answers" do
      with_read_timeout(0.2)
      with_provider do |uri|
        request = Net::HTTP::Post.new(uri).tap { |post| post.set_form_data(code: "c") }
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        expect(perform(uri, request)).to be_nil
        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 5
      end
    end

    # Net::HTTP retries an idempotent request once after a timeout, on a fresh connection. Left on,
    # the GitHub profile and email reads are each allowed double the timeout — which is how a bound
    # advertised as fifteen seconds a call quietly becomes thirty.
    it "does not retry a GET that timed out" do
      with_read_timeout(0.2)
      with_provider do |uri, connections|
        expect(perform(uri, Net::HTTP::Get.new(uri))).to be_nil
        expect(connections.size).to eq(1)
      end
    end

    # A timeout is now the likeliest way for this line to fire, and its message alone names neither
    # the provider nor the call.
    it "logs what failed and where: the exception, the method, the host and path — never the query" do
      allow(Rails.logger).to receive(:warn)
      with_read_timeout(0.2)
      with_provider do |uri|
        uri.query = "code=secret"
        perform(uri, Net::HTTP::Get.new(uri))
      end

      expect(Rails.logger).to have_received(:warn).with(
        a_string_matching(%r{\ALevelcode OAuth HTTP error: Net::ReadTimeout: .* \(GET 127\.0\.0\.1/token\)\z})
      )
    end

    # Changing one of these is a decision about how long a person waits on a spinner. This makes it
    # a visible one.
    it "allows a call five seconds to connect and ten to answer, once" do
      expect(described_class::HTTP_OPTIONS).to eq(open_timeout: 5, read_timeout: 10, write_timeout: 10, max_retries: 0)
    end
  end
end
