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
end
