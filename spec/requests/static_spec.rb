require 'rails_helper'

# Strict host <-> brand isolation (StaticController#ui): thin.ly serves ONLY the shortener,
# levelcode.ai serves ONLY the LevelCode Cloud account app.
RSpec.describe "Static host/brand isolation", type: :request do
  # The two shells. A 200 cannot tell them apart, and telling them apart is the point of this file.
  let(:shortener_shell) { "static/ui" }
  let(:account_shell)   { "static/ui_levelcode" }

  # Run an example under a different host policy — what LEVELCODE_HOSTS / LEVELCODE_ORIGIN would set.
  def with_levelcode_hosts(hosts: Levelcode::Hosts::DEFAULT_HOSTS, origin: Levelcode::Hosts::DEFAULT_ORIGIN)
    allow(Levelcode::Hosts).to receive(:current).and_return(Levelcode::Hosts.new(hosts: hosts, origin: origin))
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

  # Rack passes `req.host` through exactly as the client sent it (only the port is stripped), so
  # routing and the controller both have to fold case — or a 7-char bare path like /pricing
  # resolves as a short code before #ui ever runs.
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
end
