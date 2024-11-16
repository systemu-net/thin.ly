require 'rails_helper'

RSpec.describe "Links", type: :request do
  describe "GET /api/v1/index" do
    it "returns http success" do
      get "/api/v1/links"
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /api/v1/create" do
    it "returns http success" do
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
