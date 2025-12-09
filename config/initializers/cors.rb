# config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  # Health check endpoint - no origin restrictions
  allow do
    origins "*"
    resource "/health", headers: :any, methods: [ :get ]
  end

  allow do
    origins(
      "http://localhost:4000",
      "http://localhost:3000",
      ENV["DEV_HOST"],
      "https://thin.ly",
      "https://www.thin.ly",
      "https://app.thin.ly"
    )
    resource(
      "*",
      headers: :any,
      expose: [ "access-token", "expiry", "token-type", "Authorization" ],
      methods: [ :get, :patch, :put, :delete, :post, :options, :show ]
    )
  end
end
