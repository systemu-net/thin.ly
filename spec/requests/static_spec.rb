require 'rails_helper'

# Strict host <-> brand isolation (StaticController#ui): thin.ly serves ONLY the shortener,
# levelcode.ai serves ONLY the LevelCode Cloud account app.
RSpec.describe "Static host/brand isolation", type: :request do
  describe "on the thin.ly (shortener) host" do
    before { host! "thin.ly" }

    it "serves the shortener shell at the root" do
      get "/"
      expect(response).to have_http_status(:ok)
    end

    it "does NOT open LevelCode Cloud from /ai — it 301s to the canonical LevelCode origin" do
      get "/ai"
      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to("https://levelcode.ai/ai")
    end

    it "bounces a deep /ai/* path to levelcode.ai, preserving path + query" do
      get "/ai/account?tab=usage"
      expect(response).to redirect_to("https://levelcode.ai/ai/account?tab=usage")
    end
  end

  describe "on the levelcode.ai (account app) host" do
    before { host! "levelcode.ai" }

    it "renders the LevelCode Cloud shell under /ai" do
      get "/ai/account"
      expect(response).to have_http_status(:ok)
    end

    it "never serves the shortener shell — a bare path funnels into /ai" do
      get "/pricing"
      expect(response).to redirect_to("/ai/pricing")
    end

    it "funnels the root into /ai" do
      get "/"
      expect(response).to redirect_to("/ai")
    end
  end
end
