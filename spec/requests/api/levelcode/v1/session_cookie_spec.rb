require "rails_helper"

# The account site's web session, at the LevelCode API. The API takes the levelcode.ai session cookie as well as an
# editor's bearer token, and as a token-first API it has no CSRF token. SameSite=Lax is a SITE boundary: a page on
# another origin of the same site — the web editor at app.levelcode.ai — is sent the cookie too. So the cookie counts
# only on a request from the account site's own pages (or one the visitor typed); a page anywhere else has to bring a
# token, as the editor does.
RSpec.describe "LevelCode API: the web session cookie", type: :request do
  PROFILE = "/api/levelcode/v1/account/profile".freeze

  let(:user) { create(:user, email: "cookie@example.com") }

  before do
    allow(Stripe::Customer).to receive(:create).and_return(Stripe::Customer.construct_from(id: "cus_test"))
    sign_in user
  end

  def profile(headers = {})
    get PROFILE, headers: headers
  end

  it "counts on a request from the account site's own pages" do
    profile("Sec-Fetch-Site" => "same-origin")

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["email"]).to eq("cookie@example.com")
  end

  it "counts on an address the visitor opened themselves (no page sent it)" do
    profile("Sec-Fetch-Site" => "none")

    expect(response).to have_http_status(:ok)
  end

  it "does not count from another origin of the same site — the web editor's page, or any subdomain" do
    profile("Sec-Fetch-Site" => "same-site", "Origin" => "https://app.levelcode.ai")

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body.dig("error", "code")).to eq("unauthorized")
  end

  it "does not count from another site" do
    profile("Sec-Fetch-Site" => "cross-site", "Origin" => "https://evil.example")

    expect(response).to have_http_status(:unauthorized)
  end

  # (One request per example: the test sign-in holds for the request that follows it.)
  it "does not let another origin start a checkout with it" do
    allow(Stripe::Checkout::Session).to receive(:create)

    post "/api/levelcode/v1/checkouts", params: { plan: "pro" }.to_json,
         headers: { "Sec-Fetch-Site" => "same-site", "Origin" => "https://app.levelcode.ai", "CONTENT_TYPE" => "text/plain" }

    expect(response).to have_http_status(:unauthorized)
    expect(Stripe::Checkout::Session).not_to have_received(:create)
  end

  it "does not let another origin open the billing portal with it" do
    allow(Stripe::BillingPortal::Session).to receive(:create)

    post "/api/levelcode/v1/billings", headers: { "Sec-Fetch-Site" => "same-site", "Origin" => "https://app.levelcode.ai" }

    expect(response).to have_http_status(:unauthorized)
    expect(Stripe::BillingPortal::Session).not_to have_received(:create)
  end

  describe "from a browser that sends no Sec-Fetch-Site (older than 2023)" do
    it "counts with no Origin" do
      profile

      expect(response).to have_http_status(:ok)
    end

    it "counts with this site's own Origin" do
      profile("Origin" => "http://www.example.com")   # the test request's own origin

      expect(response).to have_http_status(:ok)
    end

    it "does not count with another origin's" do
      profile("Origin" => "https://app.levelcode.ai")

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "an editor's bearer token" do
    around do |example|
      prev = ENV["LEVELCODE_JWT_SECRET"]
      ENV["LEVELCODE_JWT_SECRET"] = "test-levelcode-secret"
      example.run
    ensure
      ENV["LEVELCODE_JWT_SECRET"] = prev
    end

    it "still counts from the editor's page, where the cookie does not" do
      sign_out user
      token = Levelcode::EditorToken.mint_access(user)

      profile("Sec-Fetch-Site" => "same-site", "Origin" => "https://app.levelcode.ai", "Authorization" => "Bearer #{token}")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["email"]).to eq("cookie@example.com")
    end
  end
end
