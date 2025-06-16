unless Rails.env.test?
  Stripe.api_key = ENV["STRIPE_SECRET_KEY"] || Rails.application.credentials.stripe_secret_key
end
