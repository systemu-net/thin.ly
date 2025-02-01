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
        links.as_json(only: %i[lookup_code original_url created_at updated_at])
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
        "created_at" => link.created_at.as_json,
        "updated_at" => link.updated_at.as_json
      })
    end
  end
end
