# config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "http://localhost:4000", "http://localhost:3000", ENV["DEV_HOST"]
    resource(
      "*",
      headers: :any,
      expose: [ "access-token", "expiry", "token-type", "Authorization" ],
      methods: [ :get, :patch, :put, :delete, :post, :options, :show ]
    )
  end
end

Rails.application.config.hosts << ENV["DEV_HOST"].split("//").last
