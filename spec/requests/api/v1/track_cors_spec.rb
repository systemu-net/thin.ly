require 'rails_helper'

# Exercises the real Rack::Cors middleware stack to prove that published pages
# served from *.thin.ly subdomains are allowed to POST analytics beacons.
RSpec.describe "Track endpoint CORS", type: :request do
  let(:subdomain_origin) { "https://l381z6.thin.ly" }

  describe "preflight (OPTIONS) for /api/v1/track/view" do
    it "allows a *.thin.ly subdomain origin" do
      process(
        :options,
        "/api/v1/track/view",
        headers: {
          "HTTP_ORIGIN" => subdomain_origin,
          "HTTP_ACCESS_CONTROL_REQUEST_METHOD" => "POST",
          "HTTP_ACCESS_CONTROL_REQUEST_HEADERS" => "content-type"
        }
      )

      expect(response.headers["Access-Control-Allow-Origin"]).to eq(subdomain_origin)
      expect(response.headers["Access-Control-Allow-Methods"].to_s.upcase).to include("POST")
    end

    it "still allows the production apex origin" do
      process(
        :options,
        "/api/v1/track/view",
        headers: {
          "HTTP_ORIGIN" => "https://thin.ly",
          "HTTP_ACCESS_CONTROL_REQUEST_METHOD" => "POST",
          "HTTP_ACCESS_CONTROL_REQUEST_HEADERS" => "content-type"
        }
      )

      expect(response.headers["Access-Control-Allow-Origin"]).to eq("https://thin.ly")
    end

    it "does not allow a non-thin.ly origin" do
      process(
        :options,
        "/api/v1/track/view",
        headers: {
          "HTTP_ORIGIN" => "https://evil.example.com",
          "HTTP_ACCESS_CONTROL_REQUEST_METHOD" => "POST",
          "HTTP_ACCESS_CONTROL_REQUEST_HEADERS" => "content-type"
        }
      )

      expect(response.headers["Access-Control-Allow-Origin"]).to be_nil
    end
  end

  describe "actual POST /api/v1/track/view" do
    it "echoes the Access-Control-Allow-Origin for a subdomain page" do
      page = create(:brand_page)

      post(
        "/api/v1/track/view",
        params: { lookup_code: page.lookup_code }.to_json,
        headers: {
          "HTTP_ORIGIN" => subdomain_origin,
          "CONTENT_TYPE" => "application/json"
        }
      )

      expect(response).to have_http_status(:ok)
      expect(response.headers["Access-Control-Allow-Origin"]).to eq(subdomain_origin)
    end
  end
end
