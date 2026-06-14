require 'rails_helper'

RSpec.describe "Api::V1::BrandPages analytics", type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: 'cus_test123'))
  end

  def entry_for(json, lookup_code)
    json["pages"].find { |p| p["lookup_code"] == lookup_code }
  end

  describe "GET /api/v1/brand_pages/analytics" do
    context "when user is not authenticated" do
      it "returns unauthorized status" do
        get "/api/v1/brand_pages/analytics"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      before { sign_in user }

      it "returns an entry per draft, keyed by the draft lookup_code" do
        draft_a = create(:brand_page, :draft, user: user)
        draft_b = create(:brand_page, :draft, user: user)

        get "/api/v1/brand_pages/analytics", headers: auth_headers(user)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["window_days"]).to eq(BrandPageAnalyticsService::WINDOW_DAYS)
        expect(json["pages"].map { |p| p["lookup_code"] }).to contain_exactly(draft_a.lookup_code, draft_b.lookup_code)
      end

      it "reports zeros for a draft that was never published" do
        draft = create(:brand_page, :draft, user: user)

        get "/api/v1/brand_pages/analytics", headers: auth_headers(user)
        entry = entry_for(JSON.parse(response.body), draft.lookup_code)

        expect(entry).to include("views" => 0, "views_window" => 0, "trend_pct" => 0)
        expect(entry["spark"]).to eq(Array.new(BrandPageAnalyticsService::WINDOW_DAYS, 0))
      end

      it "counts the published version's page_views against the draft" do
        draft = create(:brand_page, :draft, :with_published_version, user: user)
        published = draft.reload.published_version

        # 3 views inside the current 14-day window, 1 older than 28 days
        create(:page_view, brand_page: published, visited_at: 1.day.ago)
        create(:page_view, brand_page: published, visited_at: 2.days.ago)
        create(:page_view, brand_page: published, visited_at: 3.days.ago)
        create(:page_view, brand_page: published, visited_at: 40.days.ago)

        get "/api/v1/brand_pages/analytics", headers: auth_headers(user)
        entry = entry_for(JSON.parse(response.body), draft.lookup_code)

        expect(entry["views"]).to eq(4)         # all-time
        expect(entry["views_window"]).to eq(3)  # last 14 days
        expect(entry["spark"].sum).to eq(3)
        expect(entry["spark"].length).to eq(BrandPageAnalyticsService::WINDOW_DAYS)
      end

      it "computes trend_pct vs the previous window" do
        draft = create(:brand_page, :draft, :with_published_version, user: user)
        published = draft.reload.published_version

        # current window: 4 views, previous window: 2 views → +100%
        create_list(:page_view, 4, brand_page: published, visited_at: 2.days.ago)
        create_list(:page_view, 2, brand_page: published, visited_at: 20.days.ago)

        get "/api/v1/brand_pages/analytics", headers: auth_headers(user)
        entry = entry_for(JSON.parse(response.body), draft.lookup_code)

        expect(entry["views_window"]).to eq(4)
        expect(entry["trend_pct"]).to eq(100)
      end

      it "does not include other users' pages" do
        create(:brand_page, :draft, user: other_user)
        mine = create(:brand_page, :draft, user: user)

        get "/api/v1/brand_pages/analytics", headers: auth_headers(user)
        json = JSON.parse(response.body)

        expect(json["pages"].map { |p| p["lookup_code"] }).to eq([ mine.lookup_code ])
      end
    end
  end
end
