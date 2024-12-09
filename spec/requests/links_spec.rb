require 'rails_helper'

RSpec.describe "Links", type: :request do
  describe "GET /api/v1/index" do
    let(:user) { create(:user) }
    let(:link) { create(:link, user: user) }

    it "returns http success" do
      link
      sign_in(user)

      get "/api/v1/links"

      links = assigns(:links)

      expect(response).to have_http_status(:success)
      expect(response_body).to eq(links.as_json)
    end
  end

  describe "POST /api/v1/create" do
    let(:user) { create(:user) }

    it "returns http success" do
      sign_in(user)
      post "/api/v1/links", params: { link: { original_url: 'https://www.thin.ly/example' } }

      link = assigns(:link)
      expect(response).to have_http_status(:created)
      expect(response_body).to eq({
        "lookup_code" => link.lookup_code,
        "created_at" => link.created_at.as_json,
        "updated_at" => link.updated_at.as_json
      })
    end
  end
end
