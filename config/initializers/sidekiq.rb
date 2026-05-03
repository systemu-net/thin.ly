unless Rails.env.test?
  Sidekiq.configure_server do |config|
    config.redis = {
      url: ENV.fetch("REDIS_URL"),
      timeout: 10,
      reconnect_attempts: 3
    }

    schedule_file = Rails.root.join("config", "schedule.yml")
    if File.exist?(schedule_file)
      Sidekiq::Cron::Job.load_from_hash YAML.load_file(schedule_file)
    else
      Rails.logger.warn("Schedule file #{schedule_file} not found. No scheduled jobs will be loaded.")
    end
  end

  Sidekiq.configure_client do |config|
    config.redis = {
      url: ENV.fetch("REDIS_URL"),
      timeout: 10,
      reconnect_attempts: 3
    }
  end
end
