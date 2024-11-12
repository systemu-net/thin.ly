require 'rails_helper'

RSpec.describe "Links", type: :request do
  describe "GET /all" do
    it "returns http success" do
      get "/links/all"
      expect(response).to have_http_status(:success)
    end
  end

end
