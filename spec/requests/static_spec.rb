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

  # A half-applied staging override — LEVELCODE_ORIGIN pointed at a tunnel while LEVELCODE_HOSTS still
  # listed only production — made /ai/login 301 to itself, forever. The browser follows the redirect
  # straight back into this action and the log fills with identical 301s.
  describe "when the canonical origin IS the host being asked" do
    before do
      stub_const("StaticController::LEVELCODE_ORIGIN", "https://thinly.ngrok.app")
      host! "thinly.ngrok.app"
    end

    it "serves the account app instead of redirecting to itself" do
      get "/ai/login"
      expect(response).to have_http_status(:ok)
      expect(response).not_to have_http_status(:moved_permanently)
    end

    it "still serves the shortener shell on a non-/ai path" do
      get "/"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "LEVELCODE_HOSTS from the environment" do
    it "treats a configured tunnel host as a LevelCode host" do
      stub_const("StaticController::LEVELCODE_HOSTS", %w[levelcode.ai www.levelcode.ai thinly.ngrok.app])
      host! "thinly.ngrok.app"
      get "/ai/login"
      expect(response).to have_http_status(:ok)
    end

    it "funnels a bare path into /ai on that host, exactly as production does" do
      stub_const("StaticController::LEVELCODE_HOSTS", %w[levelcode.ai thinly.ngrok.app])
      host! "thinly.ngrok.app"
      get "/pricing"
      expect(response).to redirect_to("/ai/pricing")
    end

    it "parses a comma list, trimming and dropping blanks" do
      # The REAL parser, not a copy of it — asserting a re-implementation against itself proves
      # nothing about the constant the controller actually uses.
      expect(StaticController.parse_hosts("levelcode.ai, WWW.LevelCode.ai ,thinly.ngrok.app,"))
        .to eq(%w[levelcode.ai www.levelcode.ai thinly.ngrok.app])
      expect(StaticController.parse_hosts("")).to eq([])
      expect(StaticController.parse_hosts(nil)).to eq([])
    end

    it "builds the constant from the environment, not from a literal" do
      # Asserted against the SOURCE. The constant is frozen at class load, so nothing a spec sets in
      # ENV can rebuild it — and comparing the value to parse_hosts(default) passes just as happily
      # when someone hardcodes the array back, because with no override the two are identical. The
      # only thing that actually distinguishes them is how the constant is written.
      src = Rails.root.join("app/controllers/static_controller.rb").read
      expect(src).to match(/LEVELCODE_HOSTS\s*=\s*parse_hosts\(ENV\.fetch\("LEVELCODE_HOSTS"/),
                    "LEVELCODE_HOSTS must be built from ENV, or a tunnel host can never serve /ai"
      expect(StaticController::DEFAULT_LEVELCODE_HOSTS).to include("levelcode.ai")
    end
  end
end
