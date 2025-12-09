unless Rails.env.test?
  Sidekiq.configure_server do |config|
    config.redis = {
      url: ENV.fetch("REDIS_URL"),
      timeout: 10,
      reconnect_attempts: 3
    }
  end

  Sidekiq.configure_client do |config|
    config.redis = {
      url: ENV.fetch("REDIS_URL"),
      timeout: 10,
      reconnect_attempts: 3
    }
  end
end
