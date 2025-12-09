unless Rails.env.test?
  $redis = Redis.new(
    url: ENV.fetch("REDIS_URL"),
    timeout: 10, # Increase timeout for slower networks
    reconnect_attempts: 3
  )
end
