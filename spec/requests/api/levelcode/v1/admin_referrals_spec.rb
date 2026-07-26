require "rails_helper"

RSpec.describe "Api::Levelcode::V1::Admin referrals", type: :request do
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

  def attribution(source, handle)
    { "source" => source, "params" => { source => handle }, "recorded_at" => Time.current.utc.iso8601 }
  end

  def row_for(body, channel)
    body["rows"].find { |r| r["channel"] == channel }
  end

  describe "authorization" do
    it "403s for a non-admin" do
      as_user(member)
      get "/api/levelcode/v1/admin/referrals"
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("forbidden")
    end
  end

  describe "GET /admin/referrals" do
    before { as_user(admin) }

    it "counts signups per channel and keeps the partner handle" do
      create(:user, email: "a@example.com", signup_attribution: attribution("linkedin", "anastasia"))
      create(:user, email: "b@example.com", signup_attribution: attribution("linkedin", "anastasia"))
      create(:user, email: "c@example.com", signup_attribution: attribution("youtube", "koderrsha"))

      get "/api/levelcode/v1/admin/referrals"
      expect(response).to have_http_status(:ok)
      body = response.parsed_body

      expect(row_for(body, "linkedin")).to include("signups" => 2, "handle" => "anastasia")
      expect(row_for(body, "youtube")).to include("signups" => 1, "handle" => "koderrsha")
      expect(body.dig("totals", "signups")).to eq(3)
    end

    it "reports signups with no attribution separately rather than as a channel" do
      create(:user, email: "organic@example.com") # no signup_attribution

      get "/api/levelcode/v1/admin/referrals"
      body = response.parsed_body

      # admin + member + organic all have nil attribution
      expect(body["unattributed_signups"]).to be >= 1
      expect(body["rows"].map { |r| r["channel"] }).not_to include(nil, "")
    end

    it "counts human clicks per channel from the link destination, excluding bots" do
      owner = create(:user, email: "owner@example.com")
      link = create(:link, user: owner, original_url: "https://levelcode.ai/ai?linkedin=anastasia")

      2.times { Click.create!(link: link, is_bot: false, created_at: 1.day.ago) }
      Click.create!(link: link, is_bot: true, created_at: 1.day.ago)

      get "/api/levelcode/v1/admin/referrals"
      expect(row_for(response.parsed_body, "linkedin")).to include("clicks" => 2)
    end

    it "ignores links that do not point at the product" do
      owner = create(:user, email: "owner2@example.com")
      other = create(:link, user: owner, original_url: "https://example.com/?linkedin=anastasia")
      Click.create!(link: other, is_bot: false, created_at: 1.day.ago)

      get "/api/levelcode/v1/admin/referrals"
      expect(response.parsed_body.dig("totals", "clicks")).to eq(0)
    end

    it "counts a signup as paid only on a non-free levelcode wallet with budget" do
      paid = create(:user, email: "paid@example.com", signup_attribution: attribution("linkedin", "anastasia"))
      free = create(:user, email: "free@example.com", signup_attribution: attribution("linkedin", "anastasia"))

      CreditWallet.create!(user: paid, product: "levelcode", plan_key: "orbits_pro",
                           input_cap: 1, output_cap: 1, budget_micros: 5_000_000,
                           period_start: Time.current, period_end: 1.month.from_now, overage_policy: "throttle")
      CreditWallet.create!(user: free, product: "levelcode", plan_key: "free",
                           input_cap: 1, output_cap: 1, budget_micros: 0,
                           period_start: Time.current, period_end: 1.month.from_now, overage_policy: "throttle")

      get "/api/levelcode/v1/admin/referrals"
      expect(row_for(response.parsed_body, "linkedin")).to include("signups" => 2, "paid" => 1)
    end

    it "honours the date range on both signups and clicks" do
      old_user = create(:user, email: "old@example.com", signup_attribution: attribution("linkedin", "anastasia"))
      old_user.update_column(:created_at, 90.days.ago)

      owner = create(:user, email: "owner3@example.com")
      link = create(:link, user: owner, original_url: "https://levelcode.ai/ai?linkedin=anastasia")
      Click.create!(link: link, is_bot: false, created_at: 90.days.ago)

      get "/api/levelcode/v1/admin/referrals" # defaults to the last 30 days
      expect(response.parsed_body.dig("totals", "signups")).to eq(0)
      expect(response.parsed_body.dig("totals", "clicks")).to eq(0)

      from = 100.days.ago.to_date.iso8601
      get "/api/levelcode/v1/admin/referrals", params: { from: from, to: Date.current.iso8601 }
      expect(row_for(response.parsed_body, "linkedin")).to include("signups" => 1, "clicks" => 1)
    end

    it "states the basis for the paid column so it is not read as a conversion event" do
      get "/api/levelcode/v1/admin/referrals"
      expect(response.parsed_body["paid_basis"]).to eq("signed_up_in_range_and_paying_now")
    end

    it "400s on an unparseable date instead of 500ing" do
      get "/api/levelcode/v1/admin/referrals", params: { from: "not-a-date" }
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.dig("error", "code")).to eq("bad_request")
    end
  end
end
