unless Rails.env.test?
  Stripe.api_key = ENV["STRIPE_TEST_SECRET_KEY"] || Rails.application.credentials.stripe_test_secret_key
end
