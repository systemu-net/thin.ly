unless Rails.env.test?
  Stripe.api_key = ENV["STRIPE_SECRET_KEY"] || Rails.application.credentials.stripe_secret_key
  Stripe.api_version = "2026-01-28.clover" # Latest stable API version
end
