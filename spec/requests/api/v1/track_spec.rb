require 'rails_helper'

RSpec.describe "Api::V1::Track", type: :request do
  let(:user) { create(:user) }
  let(:brand_page) { create(:brand_page, :published, user: user) }

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: 'cus_test123'))
  end

  describe "POST /api/v1/track/view" do
    context "with valid lookup_code" do
      it "tracks the page view" do
        expect {
          post "/api/v1/track/view", params: { lookup_code: brand_page.lookup_code }, headers: {
            'Origin' => 'https://test.thin.ly',
            'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
            'Referer' => 'https://www.google.com',
            'X-Forwarded-For' => '192.168.1.1'
          }
        }.to change(PageView, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['success']).to be true

        page_view = PageView.last
        expect(page_view.brand_page).to eq(brand_page)
        expect(page_view.ip_address).to eq('192.168.1.1')
        expect(page_view.user_agent).to include('Chrome')
        expect(page_view.referrer).to eq('https://www.google.com')
        expect(page_view.browser).to eq('Chrome')
        expect(page_view.os).to eq('macOS')
        expect(page_view.device_type).to eq('desktop')
      end
    end

    context "with invalid lookup_code" do
      it "returns not found error" do
        post "/api/v1/track/view", params: { lookup_code: 'invalid' }, headers: {
          'Origin' => 'https://test.thin.ly'
        }

        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)['error']).to eq('Brand page not found')
      end
    end

    context "with mobile user agent" do
      it "detects mobile device type" do
        post "/api/v1/track/view", params: { lookup_code: brand_page.lookup_code }, headers: {
          'Origin' => 'https://test.thin.ly',
          'User-Agent' => 'Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15',
          'X-Forwarded-For' => '192.168.1.1'
        }

        expect(response).to have_http_status(:ok)

        page_view = PageView.last
        expect(page_view.device_type).to eq('mobile')
        expect(page_view.os).to eq('iOS')
      end
    end
  end
end
