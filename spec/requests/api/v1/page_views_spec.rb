require 'rails_helper'

RSpec.describe "Api::V1::PageViews", type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let!(:brand_page1) { create(:brand_page, user: user) }
  let!(:brand_page2) { create(:brand_page, user: user) }
  let!(:other_brand_page) { create(:brand_page, user: other_user) }

  let!(:page_view1) { create(:page_view, brand_page: brand_page1, visited_at: 1.hour.ago) }
  let!(:page_view2) { create(:page_view, brand_page: brand_page1, visited_at: 2.hours.ago) }
  let!(:page_view3) { create(:page_view, brand_page: brand_page2, visited_at: 3.hours.ago) }
  let!(:other_page_view) { create(:page_view, brand_page: other_brand_page) }

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: 'cus_test123'))
  end

  describe "GET /api/v1/page_views" do
    context "when user is authenticated" do
      before do
        sign_in user
      end

      it "returns all page views for the current user's brand pages" do
        get "/api/v1/page_views", headers: auth_headers(user)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json['page_views'].count).to eq(3)
        expect(json['page_views'].map { |pv| pv['id'] }).to contain_exactly(
          page_view1.id, page_view2.id, page_view3.id
        )
        expect(json['page_views'].map { |pv| pv['id'] }).not_to include(other_page_view.id)
      end

      it "orders page views by visited_at descending" do
        get "/api/v1/page_views", headers: auth_headers(user)

        json = JSON.parse(response.body)
        expect(json['page_views'].first['id']).to eq(page_view1.id)
        expect(json['page_views'].last['id']).to eq(page_view3.id)
      end

      it "includes pagination metadata" do
        get "/api/v1/page_views", headers: auth_headers(user)

        json = JSON.parse(response.body)
        expect(json['meta']).to include(
          'current_page' => 1,
          'per_page' => 50,
          'total_count' => 3,
          'total_pages' => 1
        )
      end

      it "supports pagination" do
        get "/api/v1/page_views?page=1&per_page=2", headers: auth_headers(user)

        json = JSON.parse(response.body)
        expect(json['page_views'].count).to eq(2)
        expect(json['meta']['current_page']).to eq(1)
        expect(json['meta']['per_page']).to eq(2)
        expect(json['meta']['total_pages']).to eq(2)
      end
    end

    context "when user is not authenticated" do
      it "returns unauthorized status" do
        get "/api/v1/page_views"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "GET /api/v1/page_views/by_brand_page" do
    context "when user is authenticated" do
      before do
        sign_in user
      end

      it "returns page views for a specific brand page" do
        get "/api/v1/page_views/by_brand_page?lookup_code=#{brand_page1.lookup_code}",
            headers: auth_headers(user)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json['page_views'].count).to eq(2)
        expect(json['page_views'].map { |pv| pv['id'] }).to contain_exactly(
          page_view1.id, page_view2.id
        )
        expect(json['brand_page']['lookup_code']).to eq(brand_page1.lookup_code)
      end

      it "returns error when lookup_code is missing" do
        get "/api/v1/page_views/by_brand_page", headers: auth_headers(user)

        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)['error']).to eq('lookup_code parameter is required')
      end

      it "returns error when brand page is not found" do
        get "/api/v1/page_views/by_brand_page?lookup_code=invalid",
            headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)['error']).to eq('Brand page not found')
      end

      it "returns error when trying to access another user's brand page" do
        get "/api/v1/page_views/by_brand_page?lookup_code=#{other_brand_page.lookup_code}",
            headers: auth_headers(user)

        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)['error']).to eq('Brand page not found')
      end

      it "includes brand page information in response" do
        get "/api/v1/page_views/by_brand_page?lookup_code=#{brand_page1.lookup_code}",
            headers: auth_headers(user)

        json = JSON.parse(response.body)
        expect(json['brand_page']).to include(
          'lookup_code' => brand_page1.lookup_code,
          'title' => brand_page1.title,
          'status' => brand_page1.status
        )
      end
    end

    context "when user is not authenticated" do
      it "returns unauthorized status" do
        get "/api/v1/page_views/by_brand_page?lookup_code=#{brand_page1.lookup_code}"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  def auth_headers(user)
    token = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil).first
    { 'Authorization' => "Bearer #{token}" }
  end
end
