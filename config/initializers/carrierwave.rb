# frozen_string_literal: true

CarrierWave.configure do |config|
  config.fog_credentials = {
    provider: "AWS",
    aws_access_key_id: ENV["AWS_ACCESS_KEY_ID"],
    aws_secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
    region: ENV["AWS_REGION"]
  }
  config.fog_use_ssl_for_aws = false
  config.storage = :fog
  config.fog_directory = ENV["S3_BUCKET"]
end

# carrieewave testing
if Rails.env.test?
  CarrierWave.configure do |config|
    config.storage = :file
    config.enable_processing = false
    config.skip_ssrf_protection = true
  end
end
