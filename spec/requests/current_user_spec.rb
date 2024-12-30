require 'rails_helper'

RSpec.describe "CurrentUsers", type: :request do
  describe "GET /api/v1/current_user" do
    let(:user) { create(:user) }
    let(:headers) { auth_headers(user) }

    it "returns http success" do
      get "/api/v1/current_user", headers: headers

      expect(response).to have_http_status(:success)
    end
  end
end
