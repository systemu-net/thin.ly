require "rails_helper"

# `config.force_ssl = true` switches on ActionDispatch::SSL, which does THREE separate jobs: redirect
# http->https, send Strict-Transport-Security, and flag cookies `Secure`. This app wants the last two
# and specifically not the first, because the ALB health check reaches the instance over plain HTTP.
#
# Getting that wrong is not a subtle bug: `.ebextensions/03_healthcheck.config` pins
# `MatcherHTTPCode: "200"`, so a redirect on /up is a 301, every instance is marked unhealthy, and the
# site goes down. These specs exist because that is a one-word mistake with an outage attached.
RSpec.describe "production SSL configuration" do
  PRODUCTION_RB = Rails.root.join("config/environments/production.rb").freeze
  HEALTHCHECK_CONFIG = Rails.root.join(".ebextensions/03_healthcheck.config").freeze

  let(:production_source) { File.read(PRODUCTION_RB) }

  # Rack 3 downcases response header names. Looking only for "Location" would make the no-redirect
  # assertion pass whether or not a redirect happened — it was written that way first, and the
  # deliberately-failing companion spec below is what exposed it.
  def location(headers)
    headers["location"] || headers["Location"]
  end

  describe "the health check cannot be redirected" do
    # The mechanism itself, exercised rather than assumed: with `redirect: false`, a plain-HTTP request
    # passes straight through instead of being bounced to https.
    it "passes a plain-HTTP /up through untouched" do
      inner = ->(_env) { [200, { "Content-Type" => "text/plain" }, ["ok"]] }
      ssl = ActionDispatch::SSL.new(inner, redirect: false, secure_cookies: true,
                                           hsts: { expires: 1.week, subdomains: false, preload: false })

      status, headers, _body = ssl.call(Rack::MockRequest.env_for("http://levelcode.ai/up"))

      expect(status).to eq(200), "the ALB matcher pins 200; a redirect here marks every instance unhealthy"
      expect(location(headers)).to be_nil
    end

    # …and the contrast, so the spec above is not passing for some unrelated reason: the SAME request
    # WOULD be redirected if the option were flipped back on. This is the outage, reproduced.
    it "WOULD redirect it if `redirect` were ever turned back on" do
      inner = ->(_env) { [200, {}, ["ok"]] }
      ssl = ActionDispatch::SSL.new(inner, redirect: {}, secure_cookies: true, hsts: { expires: 1.week })

      status, headers, _body = ssl.call(Rack::MockRequest.env_for("http://levelcode.ai/up"))

      expect(status).to eq(301)
      expect(location(headers)).to start_with("https://")
    end

    it "still needs to care, because the ALB matcher accepts only a 200" do
      # If the health check were ever loosened to accept 3xx, the guards above would be belt-and-braces
      # rather than load-bearing — worth knowing, so the two files are read together.
      health = File.read(HEALTHCHECK_CONFIG)
      expect(health).to include('MatcherHTTPCode: "200"')
      expect(health).to include("HealthCheckPath: /up")
    end
  end

  describe "what production actually declares" do
    it "keeps the redirect off" do
      expect(production_source).to match(/redirect:\s*false/),
                                   "ActionDispatch::SSL would redirect the plain-HTTP health check"
    end

    it "turns on the two things we DO want from force_ssl" do
      expect(production_source).to match(/config\.force_ssl\s*=\s*true/)
      expect(production_source).to match(/secure_cookies:\s*true/)
      expect(production_source).to match(/hsts:\s*\{/)
    end

    it "keeps HSTS conservative until it has been proven in production" do
      # A browser honours HSTS for the full max-age and there is no way to withdraw it early, so this
      # ships short and narrow on purpose. Raising `expires` later is a deliberate act; discovering a
      # year-long commitment after the fact is not.
      expect(production_source).to match(/expires:\s*1\.week/),
                                   "raise this deliberately once a week has passed with no breakage"
      expect(production_source).to match(/subdomains:\s*false/),
                                   "subdomains: true commits every present AND future subdomain to HTTPS at once"
      expect(production_source).to match(/preload:\s*false/),
                                   "preload is effectively permanent — it is baked into browser binaries"
    end

    it "still assumes SSL behind the load balancer" do
      # Without this, request.ssl? is false for every proxied request and ActionDispatch::SSL would
      # never apply HSTS or the Secure flag at all — the change would be silently inert.
      expect(production_source).to match(/config\.assume_ssl\s*=\s*true/)
    end
  end

  describe "the session cookie" do
    let(:application_source) { File.read(Rails.root.join("config/application.rb")) }

    it "is Secure in production and not in development" do
      # An unconditional `secure: true` means the cookie is never sent over http://localhost, so nobody
      # can hold a session in development or in the specs.
      expect(application_source).to match(/secure:\s*Rails\.env\.production\?/)
    end

    it "stays SameSite=Lax, because the OAuth callback depends on it" do
      # :strict withholds the cookie on cross-site top-level GETs — which is exactly what Google's
      # redirect back to /ai/auth/callback is. The `state` stashed in the session would not come back
      # and every sign-in would fail with `session_expired`.
      expect(application_source).to match(/same_site:\s*:lax/)
      expect(application_source).not_to match(/same_site:\s*:strict/)
    end
  end
end
