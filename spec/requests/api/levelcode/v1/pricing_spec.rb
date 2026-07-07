require "rails_helper"

RSpec.describe "Api::Levelcode::V1::Pricing", type: :request do
  PRICING_URL = "/api/levelcode/v1/pricing"

  describe "GET /api/levelcode/v1/pricing" do
    it "is public (no auth required) and returns 200" do
      get PRICING_URL
      expect(response).to have_http_status(:ok)
    end

    it "serializes every Levelcode::PLANS tier with the SPEC §3 shape" do
      get PRICING_URL

      tiers = response.parsed_body["tiers"]
      expect(tiers).to be_an(Array)
      expect(tiers.length).to eq(Levelcode::PLANS.length)

      first = tiers.first
      expect(first.keys).to include(
        "key", "name", "price_cents", "interval",
        "input_cap", "output_cap", "turns", "features"
      )
    end

    it "surfaces the server-side plan keys and caps verbatim" do
      get PRICING_URL

      plan = Levelcode::PLANS.first
      tier = response.parsed_body["tiers"].find { |t| t["key"] == plan[:key] }

      expect(tier).to be_present
      expect(tier["price_cents"]).to eq(plan[:price_cents])
      expect(tier["input_cap"]).to eq(plan[:input_cap])
      expect(tier["output_cap"]).to eq(plan[:output_cap])
    end
  end
end
