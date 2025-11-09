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

      links = assigns(:links)

      expect(response).to have_http_status(:success)
      expect(response_body['links']).to eq(
        links.as_json(only: %i[lookup_code original_url title description created_at updated_at])
      )
    end
  end

  describe "POST /api/v1/links" do
    let(:user) { create(:user) }

    it "returns http success" do
      sign_in(user)
      post "/api/v1/links", params: { link: { original_url: 'https://www.thin.ly/example' } }

      link = assigns(:link)
      expect(response).to have_http_status(:created)
      expect(response_body['link']).to eq({
        "lookup_code" => link.lookup_code,
        "title" => link.title,
        "description" => link.description,
        "created_at" => link.created_at.as_json,
        "updated_at" => link.updated_at.as_json
      })
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
    end

    context "when user is not authenticated" do
      it "returns unauthorized" do
        get "/api/v1/links/search", params: { query: 'google' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
