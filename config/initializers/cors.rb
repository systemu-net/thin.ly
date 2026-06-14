# config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  # Health check endpoint - unrestricted for ELB health checks
  allow do
    origins "*"
    resource "/up",
      headers: :any,
      methods: [ :get, :head, :options ]
  end

  allow do
    origins(
      "http://localhost:4000",
      "http://localhost:3000",
      ENV["DEV_HOST"],
      "https://thin.ly",
      "https://www.thin.ly",
      "https://app.thin.ly",
      "https://thinly.ngrok.app",
      /.*\.elasticbeanstalk\.com$/ # Allow EB URLs
    )
    resource(
      "*",
      headers: :any,
      expose: [ "access-token", "expiry", "token-type", "Authorization" ],
      methods: [ :get, :patch, :put, :delete, :post, :options, :show ]
    )
  end

  # Published link-in-bio pages are served from per-user subdomains
  # (e.g. https://john.thin.ly). They are untrusted/public origins, so rather
  # than adding them to the catch-all above they may only reach the analytics
  # tracking endpoints. Without this, the browser's CORS preflight blocks the
  # page-view beacon and no views are recorded.
  allow do
    origins(%r{\Ahttps://[a-z0-9_-]+\.thin\.ly\z}i)
    resource(
      "/api/v1/track/*",
      headers: :any,
      methods: [ :post, :options ]
    )
  end
end
