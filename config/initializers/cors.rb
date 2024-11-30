# config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "http://localhost:4000", "http://#{Rails.application.credentials.fetch(:host_ip)}:4000"
    resource(
      "*",
      headers: :any,
      expose: [ "access-token", "expiry", "token-type", "Authorization" ],
      methods: [ :get, :patch, :put, :delete, :post, :options, :show ]
    )
  end
end
