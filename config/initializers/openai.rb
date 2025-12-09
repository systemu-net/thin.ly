unless Rails.env.test?
  OpenAI.configure do |config|
    config.access_token = ENV["OPENAI_ACCESS_TOKEN"] || Rails.application.credentials.fetch(:openai_access_token, nil)
    # Highly recommended in development, so you can see what errors OpenAI is returning.
    # Not recommended in production because it could leak private data to your logs.
    config.log_errors = true if Rails.env.development?
  end
end
