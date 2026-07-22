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
end
