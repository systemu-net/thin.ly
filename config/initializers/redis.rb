unless Rails.env.test?
  $redis = Redis.new(url: ENV.fetch("REDIS_URL"))
end
