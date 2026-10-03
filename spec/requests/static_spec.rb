require 'rails_helper'

# Strict host <-> brand isolation (StaticController#ui): thin.ly serves ONLY the shortener,
# levelcode.ai serves ONLY the LevelCode Cloud account app.
RSpec.describe "Static host/brand isolation", type: :request do
  # The two shells. A 200 cannot tell them apart, and telling them apart is the point of this file.
  let(:shortener_shell) { "static/ui" }
  let(:account_shell)   { "static/ui_levelcode" }

  # Run an example under a different host policy — what LEVELCODE_HOSTS / LEVELCODE_ORIGIN would set.
  def with_levelcode_hosts(hosts: StaticController::DEFAULT_LEVELCODE_HOSTS, origin: "https://levelcode.ai")
    stub_const("StaticController::LEVELCODE_HOSTS", StaticController.parse_hosts(hosts))
    stub_const("StaticController::LEVELCODE_ORIGIN", origin)
  end

  describe "on the thin.ly (shortener) host" do
    before { host! "thin.ly" }

    it "serves the shortener shell at the root" do
      get "/"
      expect(response).to have_http_status(:ok)
      expect(response).to render_template(shortener_shell)
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

    # The inverse of every "funnels a 7-char bare path" example below: here it IS a short code. Without
    # this, a route constraint that withheld the lookup from every host would pass the whole file.
    it "resolves a 7-char bare path as a short code — the lookup is withheld only from LevelCode hosts" do
      get "/abc1234"
      expect(response).to redirect_to("/link-not-found")
    end
  end

  describe "on the levelcode.ai (account app) host" do
    before { host! "levelcode.ai" }

    it "renders the LevelCode Cloud shell under /ai" do
      get "/ai/account"
      expect(response).to have_http_status(:ok)
      expect(response).to render_template(account_shell)
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

  # Rack passes `req.host` through exactly as the client sent it (only the port is stripped), and
  # the route constraint that keeps the shortcode lookup off LevelCode hosts compared it raw while
  # the controller downcased — so a mixed-case Host header was a LevelCode host to #ui and NOT one
  # to routing. A 7-char bare path like /pricing then resolved as a short code before #ui ever ran.
  describe "on a LevelCode host sent with a mixed-case Host header" do
    before { host! "LevelCode.AI" }

    it "funnels a 7-char bare path into /ai — routing and the controller agree on the host" do
      get "/pricing"
      expect(response).to redirect_to("/ai/pricing")
      expect(response).not_to redirect_to("/link-not-found")
    end

    it "renders the LevelCode Cloud shell under /ai" do
      get "/ai/account"
      expect(response).to have_http_status(:ok)
      expect(response).to render_template(account_shell)
    end
  end

  describe "StaticController.levelcode_host? (the ONE predicate routing and #ui share)" do
    it "normalises case exactly as parse_hosts normalises the list" do
      expect(StaticController.levelcode_host?("levelcode.ai")).to be(true)
      expect(StaticController.levelcode_host?("LevelCode.AI")).to be(true)
      expect(StaticController.levelcode_host?("WWW.LEVELCODE.AI")).to be(true)
    end

    it "is false for the shortener host, nothing, and nil" do
      expect(StaticController.levelcode_host?("thin.ly")).to be(false)
      expect(StaticController.levelcode_host?("")).to be(false)
      expect(StaticController.levelcode_host?(nil)).to be(false)
    end

    it "is what the route constraint actually calls — the two sides cannot drift apart again" do
      src = Rails.root.join("config/routes.rb").read
      expect(src).to include("StaticController.levelcode_host?(req.host)")
      expect(src).not_to match(/LEVELCODE_HOSTS\.include\?\(req\.host\)/)
    end
  end

  # A half-applied staging override — LEVELCODE_ORIGIN pointed at a tunnel while LEVELCODE_HOSTS still
  # listed only production — made /ai/login 301 to itself, forever. The browser follows the redirect
  # straight back into this action and the log fills with identical 301s.
  describe "when the canonical origin IS the host being asked" do
    before do
      with_levelcode_hosts(origin: "https://thinly.ngrok.app")
      host! "thinly.ngrok.app"
    end

    it "serves the account app instead of redirecting to itself" do
      get "/ai/login"
      expect(response).to have_http_status(:ok)
      expect(response).not_to have_http_status(:moved_permanently)
      expect(response).to render_template(account_shell)
    end

    it "still serves the shortener shell on a non-/ai path" do
      get "/"
      expect(response).to have_http_status(:ok)
      expect(response).to render_template(shortener_shell)
    end
  end

  describe "on a host that LEVELCODE_HOSTS adds (a tunnel or staging host)" do
    before do
      with_levelcode_hosts(hosts: "levelcode.ai,www.levelcode.ai,thinly.ngrok.app")
      host! "thinly.ngrok.app"
    end

    it "serves the account app under /ai" do
      get "/ai/login"
      expect(response).to have_http_status(:ok)
      expect(response).to render_template(account_shell)
    end

    # /pricing is 7 characters, so this only passes if ROUTING consults the same list the controller
    # does: the tunnel host exists nowhere but in the overridden policy.
    it "funnels a 7-char bare path into /ai, exactly as production does" do
      get "/pricing"
      expect(response).to redirect_to("/ai/pricing")
    end
  end

  describe "LEVELCODE_HOSTS from the environment" do
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
