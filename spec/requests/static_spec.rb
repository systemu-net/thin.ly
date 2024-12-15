require 'rails_helper'

RSpec.describe "Statics", type: :request do
  describe "GET /ui" do
    it "returns http success" do
      get "/static/ui"
      expect(response).to have_http_status(:success)
    end
  end

end
