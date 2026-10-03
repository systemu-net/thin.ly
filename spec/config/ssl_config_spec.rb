require "rails_helper"

# Production sits behind an ALB that terminates TLS and talks to the instance over plain HTTP. So
# ActionDispatch::SSL is on for one job — Strict-Transport-Security — and must never do its other
# one, the http->https redirect: the ALB health check accepts nothing but a 200 from /up, and a
# redirect there marks every instance unhealthy.
#
# These run the real middleware with the options production is given, so they describe what
# production does rather than what its config file looks like.
RSpec.describe "transport security in production" do
  let(:app) { ->(_env) { [ 200, { "set-cookie" => "id=1; path=/" }, [ "ok" ] ] } }
  let(:options) { Backend::Application::SSL_OPTIONS }

  def get(url, **overrides)
    Rack::MockRequest.new(ActionDispatch::SSL.new(app, **options, **overrides)).get(url)
  end

  describe "the load balancer's health check" do
    it "gets its 200 from /up over plain HTTP, never a redirect" do
      response = get("http://levelcode.ai/up")

      expect(response.status).to eq(200)
      expect(response.location).to be_nil
    end

    # The same request with the redirect left on. This is the outage — and the reason the example
    # above cannot be passing by accident.
    it "would be redirected if the redirect were ever left on" do
      response = get("http://levelcode.ai/up", redirect: {})

      expect(response.status).to eq(301)
      expect(response.location).to eq("https://levelcode.ai/up")
    end

    it "still accepts nothing but a 200 from /up" do
      health_check = YAML.load_file(Rails.root.join(".ebextensions/03_healthcheck.config"))
                         .dig("option_settings", "aws:elasticbeanstalk:environment:process:default")

      expect(health_check).to include("HealthCheckPath" => "/up", "MatcherHTTPCode" => "200")
    end
  end

  describe "Strict-Transport-Security" do
    # One assertion on the whole header: a longer max-age, includeSubDomains and preload would each
    # change it, and each is a commitment a browser holds us to with no way to withdraw it early.
    it "is sent over HTTPS for one week, for this host only" do
      expect(get("https://levelcode.ai/").headers["strict-transport-security"]).to eq("max-age=604800")
    end
  end

  describe "the session cookie" do
    let(:session_options) do
      Rails.application.middleware.find { |m| m.klass == ActionDispatch::Session::CookieStore }.args.first
    end

    # With its redirect off, ActionDispatch::SSL leaves cookies alone: Rails only flags them Secure
    # on requests it would otherwise have redirected. So the store has to carry the flag itself.
    it "is not made Secure by the middleware, which is why the store sets its own flag" do
      expect(get("https://levelcode.ai/").headers["set-cookie"]).to eq("id=1; path=/")
    end

    # :strict withholds the cookie on a cross-site top-level GET, which is exactly what a provider's
    # redirect back to /ai/auth/callback is. The `state` stashed in the session would not come back,
    # and every sign-in would fail with `session_expired`.
    it "is HttpOnly, and SameSite=Lax rather than Strict" do
      expect(session_options).to include(httponly: true, same_site: :lax)
    end

    it "is not Secure outside production, or it would never be sent over http://localhost" do
      expect(session_options).to include(secure: false)
    end
  end

  # Two things are decided only when Rails boots in production, so nothing above can observe them.
  # They are read as whole lines of code: a comment that mentions a setting is not a match.
  describe "what only a production boot evaluates" do
    def lines_of(path)
      Rails.root.join(path).readlines.map(&:strip)
    end

    it "turns the middleware on, behind the proxy, with these options" do
      expect(lines_of("config/environments/production.rb")).to include(
        "config.assume_ssl = true",
        "config.force_ssl = true",
        "config.ssl_options = Backend::Application::SSL_OPTIONS"
      )
    end

    it "marks the session cookie Secure" do
      expect(lines_of("config/application.rb")).to include("secure: Rails.env.production?,")
    end
  end
end
