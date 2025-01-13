# frozen_string_literal: true

CarrierWave.configure do |config|
  config.fog_credentials = {
    provider: "AWS",
    aws_access_key_id: Rails.application.credentials.fetch(:aws_access_key_id),
    aws_secret_access_key: Rails.application.credentials.fetch(:aws_secret_access_key),
    region: Rails.application.credentials.fetch(:aws_region)
  }
  config.fog_use_ssl_for_aws = false
  config.storage = :fog
  config.fog_directory = Rails.application.credentials.fetch(:s3_bucket)
end

# carrieewave testing
if Rails.env.test?
  CarrierWave.configure do |config|
    config.storage = :file
    config.enable_processing = false
    config.skip_ssrf_protection = true
  end
end
