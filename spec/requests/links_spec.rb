require 'rails_helper'

RSpec.describe "Links", type: :request do
  let(:stripe_customer_id) { '1234' }

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: stripe_customer_id))
  end

  describe "GET /api/v1/links" do
    let(:user) { create(:user) }
    let(:link) { create(:link, user: user) }

    it "returns http success" do
      link
      sign_in(user)

      get "/api/v1/links"

      expect(response).to have_http_status(:success)
      expect(response_body['links']).to be_an(Array)
      expect(response_body['links'].first).to include(
        'lookup_code' => link.lookup_code,
        'original_url' => link.original_url,
        'clicks_count' => 0
      )
      expect(response_body['links'].first).to have_key('is_safe')
    end

    it "includes clicks_count in the response" do
      sign_in(user)
      link_with_clicks = create(:link, user: user)
      create_list(:click, 3, link: link_with_clicks)

      get "/api/v1/links"

      expect(response).to have_http_status(:success)
      link_response = response_body['links'].find { |l| l['lookup_code'] == link_with_clicks.lookup_code }
      expect(link_response['clicks_count']).to eq(3)
    end

    it "includes is_safe in the response" do
      sign_in(user)
      safe_link = create(:link, user: user, is_safe: true)
      unsafe_link = create(:link, user: user, is_safe: false)

      get "/api/v1/links"

      expect(response).to have_http_status(:success)

      safe_response = response_body['links'].find { |l| l['lookup_code'] == safe_link.lookup_code }
      unsafe_response = response_body['links'].find { |l| l['lookup_code'] == unsafe_link.lookup_code }

      expect(safe_response['is_safe']).to eq(true)
      expect(unsafe_response['is_safe']).to eq(false)
    end
  end

  describe "POST /api/v1/links" do
    let(:user) { create(:user) }

    before do
      allow(LinkScannerJob).to receive(:perform_async).and_return(true)
      allow(QrCodeGeneratorJob).to receive(:perform_async).and_return(true)
    end

    it "returns http success" do
      sign_in(user)
      post "/api/v1/links", params: { link: { original_url: 'https://www.thin.ly/example' } }

      link = assigns(:link)
      expect(response).to have_http_status(:created)
      expect(response_body['link']).to include(
        'lookup_code' => link.lookup_code,
        'title' => link.title,
        'description' => link.description,
        'clicks_count' => 0
      )
      expect(response_body['link']).to have_key('is_safe')
      expect(response_body['link']).to have_key('created_at')
      expect(response_body['link']).to have_key('updated_at')
    end

    it "includes clicks_count and is_safe in the response" do
      sign_in(user)
      post "/api/v1/links", params: { link: { original_url: 'https://www.thin.ly/example' } }

      expect(response).to have_http_status(:created)
      expect(response_body['link']['clicks_count']).to eq(0)
      expect(response_body['link']).to have_key('is_safe')
    end
  end

  describe "GET /api/v1/links/search" do
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }

    before do
      create(:link, user: user, original_url: 'https://www.google.com', title: 'Google Search')
      create(:link, user: user, original_url: 'https://www.github.com', title: 'GitHub')
      create(:link, user: user, original_url: 'https://www.example.com', title: 'Example Site')
      create(:link, user: other_user, original_url: 'https://www.google.com', title: 'Google')
    end

    context "when user is authenticated" do
      before { sign_in(user) }

      it "searches by original_url" do
        get "/api/v1/links/search", params: { query: 'google' }

        expect(response).to have_http_status(:success)
        expect(response_body['links'].length).to eq(1)
        expect(response_body['links'][0]['original_url']).to include('google.com')
      end

      it "searches by title" do
        get "/api/v1/links/search", params: { query: 'GitHub' }

        expect(response).to have_http_status(:success)
        expect(response_body['links'].length).to eq(1)
        expect(response_body['links'][0]['title']).to eq('GitHub')
      end

      it "returns multiple results when query matches multiple links" do
        get "/api/v1/links/search", params: { query: 'com' }

        expect(response).to have_http_status(:success)
        expect(response_body['links'].length).to eq(3)
      end

      it "only returns links belonging to current user" do
        get "/api/v1/links/search", params: { query: 'google' }

        expect(response).to have_http_status(:success)
        expect(response_body['links'].length).to eq(1)
        expect(response_body['links'][0]['title']).to eq('Google Search')
      end

      it "returns error when query parameter is missing" do
        get "/api/v1/links/search"

        expect(response).to have_http_status(:bad_request)
        expect(response_body['error']).to eq('Query parameter is required')
      end

      it "returns empty array when no matches found" do
        get "/api/v1/links/search", params: { query: 'nonexistent' }

        expect(response).to have_http_status(:success)
        expect(response_body['links']).to be_empty
      end

      it "includes clicks_count and is_safe in search results" do
        link = user.links.first
        create_list(:click, 5, link: link)
        link.update(is_safe: false)

        get "/api/v1/links/search", params: { query: link.title }

        expect(response).to have_http_status(:success)
        link_response = response_body['links'].first
        expect(link_response['clicks_count']).to eq(5)
        expect(link_response['is_safe']).to eq(false)
      end
    end

    context "when user is not authenticated" do
      it "returns unauthorized" do
        get "/api/v1/links/search", params: { query: 'google' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "GET /api/v1/links/:lookup_code" do
    let(:user) { create(:user) }
    let(:link) { create(:link, user: user, is_safe: true) }

    before do
      create_list(:click, 7, link: link)
    end

    context "when user is authenticated and owns the link" do
      before { sign_in(user) }

      it "returns the link with clicks_count and is_safe" do
        get "/api/v1/links/#{link.lookup_code}"

        expect(response).to have_http_status(:success)
        expect(response_body['link']['lookup_code']).to eq(link.lookup_code)
        expect(response_body['link']['clicks_count']).to eq(7)
        expect(response_body['link']['is_safe']).to eq(true)
      end

      it "returns is_safe as false for unsafe links" do
        unsafe_link = create(:link, user: user, is_safe: false)

        get "/api/v1/links/#{unsafe_link.lookup_code}"

        expect(response).to have_http_status(:success)
        expect(response_body['link']['is_safe']).to eq(false)
      end
    end
  end

  describe "PATCH /api/v1/links/:lookup_code" do
    let(:user) { create(:user) }
    let(:link) { create(:link, user: user, is_safe: true) }

    before do
      allow(LinkScannerJob).to receive(:perform_async).and_return(true)
      create_list(:click, 3, link: link)
    end

    context "when user is authenticated and owns the link" do
      before { sign_in(user) }

      it "updates the link and returns clicks_count and is_safe" do
        patch "/api/v1/links/#{link.lookup_code}", params: {
          link: { title: 'Updated Title' }
        }

        expect(response).to have_http_status(:success)
        expect(response_body['link']['title']).to eq('Updated Title')
        expect(response_body['link']['clicks_count']).to eq(3)
        expect(response_body['link']['is_safe']).to eq(true)
      end
    end
  end

  describe "GET /:lookup_code (redirect)" do
    let(:user) { create(:user) }

    context "when link is safe" do
      let(:safe_link) { create(:link, user: user, is_safe: true, original_url: 'https://example.com') }

      it "redirects to the original URL" do
        get "/#{safe_link.lookup_code}"

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to('https://example.com')
      end

      it "logs a click" do
        expect {
          get "/#{safe_link.lookup_code}"
        }.to change { safe_link.reload.clicks_count }.from(0).to(1)
      end
    end

    context "when link is unsafe (is_safe: false)" do
      let(:unsafe_link) { create(:link, user: user, is_safe: false, original_url: 'https://malicious-site.com') }

      it "redirects to the unsafe link warning page" do
        get "/#{unsafe_link.lookup_code}"

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(unsafe_link_path)
      end

      it "does NOT redirect to the original URL" do
        get "/#{unsafe_link.lookup_code}"

        expect(response).not_to redirect_to('https://malicious-site.com')
      end

      it "does NOT log a click for unsafe links" do
        expect {
          get "/#{unsafe_link.lookup_code}"
        }.not_to change { unsafe_link.reload.clicks_count }
      end
    end

    context "when link is_safe is nil (not yet scanned)" do
      let(:unscanned_link) { create(:link, user: user, is_safe: nil, original_url: 'https://unscanned.com') }

      it "allows redirect for unscanned links" do
        get "/#{unscanned_link.lookup_code}"

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to('https://unscanned.com')
      end

      it "logs a click for unscanned links" do
        expect {
          get "/#{unscanned_link.lookup_code}"
        }.to change { unscanned_link.reload.clicks_count }.from(0).to(1)
      end
    end

    context "when link does not exist" do
      it "redirects to link not found page" do
        get "/abc1234"  # 7-character lookup code that doesn't exist

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(link_not_found_path)
      end
    end
  end

  describe "GET /link-not-found" do
    it "renders the link not found page" do
      get "/link-not-found"

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include('thin.ly')
      expect(response.body).to include('Link Not Found')
      expect(response.body).to include('deleted by its creator')
    end
  end

  describe "GET /unsafe-link" do
    it "renders the unsafe link warning page" do
      get "/unsafe-link"

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include('thin.ly')
      expect(response.body).to include('Link Blocked for Your Safety')
      expect(response.body).to include('potentially unsafe')
    end
  end
end
