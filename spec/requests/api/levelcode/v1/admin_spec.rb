require "rails_helper"

RSpec.describe "Api::Levelcode::V1::Admin", type: :request do
  let(:admin)  { create(:user, email: "admin@example.com") }
  let(:member) { create(:user, email: "member@example.com") }

  before do
    allow(admin).to receive(:role).and_return("admin")
    allow(admin).to receive(:admin?).and_return(true)
  end

  def as_user(user)
    allow_any_instance_of(Api::Levelcode::V1::BaseController).to receive(:authenticate_levelcode!).and_return(true)
    allow_any_instance_of(Api::Levelcode::V1::BaseController).to receive(:current_levelcode_user).and_return(user)
    allow_any_instance_of(Api::Levelcode::V1::BaseController).to receive(:current_user).and_return(user)
  end

  describe "authorization" do
    it "403s for a non-admin" do
      as_user(member)
      get "/api/levelcode/v1/admin/summary"
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("forbidden")
    end
  end

  describe "GET /admin/summary + /admin/users (admin)" do
    before do
      as_user(admin)
      # Two users burning tokens; one auth failure.
      UsageEvent.create!(user: admin, model: "moonshotai/kimi-k2.7-code", provider: "openrouter",
                         input_tokens: 900, output_tokens: 100, cost_micros: 50, created_at: 1.day.ago)
      UsageEvent.create!(user: member, model: "openai/gpt-oss-120b", provider: "openrouter",
                         input_tokens: 50, output_tokens: 10, cost_micros: 1, created_at: 2.days.ago)
      member.update_columns(last_country: "DE", last_seen_at: 1.hour.ago)
      AuthEvent.create!(user: member, email: member.email, kind: "login", outcome: "failure",
                        reason: "invalid_credentials", country: "DE", created_at: 1.hour.ago)
      CreditWallet.create!(user: admin, product: "levelcode", plan_key: "orbits_pro", input_cap: 15_000_000,
                           output_cap: 2_000_000, period_start: Time.current, period_end: 1.month.from_now, overage_policy: "throttle")
    end

    it "summarizes system-wide totals + breakdowns" do
      get "/api/levelcode/v1/admin/summary"

      expect(response).to have_http_status(:ok)
      s = response.parsed_body
      expect(s["input"]).to eq(950)
      expect(s["output"]).to eq(110)
      expect(s["requests"]).to eq(2)
      expect(s["active_users"]).to eq(2)
      expect(s["auth_failures"]).to eq(1)
      expect(s["plans"]).to include("Pro" => 1)
      expect(s["countries"]).to include("DE" => 1)
    end

    it "returns a per-user roll-up sorted by input tokens (top burner first)" do
      get "/api/levelcode/v1/admin/users", params: { sort: "input", dir: "desc" }

      expect(response).to have_http_status(:ok)
      users = response.parsed_body["users"]
      expect(users.first["email"]).to eq("admin@example.com")
      expect(users.first["input"]).to eq(900)
      expect(users.first["plan"]).to eq("Pro")
      member_row = users.find { |u| u["email"] == "member@example.com" }
      expect(member_row["country"]).to eq("DE")
      expect(member_row["auth_failures"]).to eq(1)
    end

    it "filters by email and by plan" do
      get "/api/levelcode/v1/admin/users", params: { q: "member" }
      expect(response.parsed_body["users"].map { |u| u["email"] }).to eq([ "member@example.com" ])

      get "/api/levelcode/v1/admin/users", params: { plan: "Pro" }
      expect(response.parsed_body["users"].map { |u| u["email"] }).to eq([ "admin@example.com" ])
    end
  end
end
