# frozen_string_literal: true

CarrierWave.configure do |config|
  config.fog_credentials = {
    provider: "AWS",
    aws_access_key_id: ENV["AWS_ACCESS_KEY_ID"] || Rails.application.credentials.fetch(:aws_access_key_id),
    aws_secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"] || Rails.application.credentials.fetch(:aws_secret_access_key),
    region: ENV["AWS_REGION"] || Rails.application.credentials.fetch(:aws_region)
  }
  config.fog_use_ssl_for_aws = false
  config.storage = :fog
  config.fog_directory = ENV["S3_BUCKET"] || Rails.application.credentials.fetch(:s3_bucket)
end

# carrieewave testing
if Rails.env.test?
  CarrierWave.configure do |config|
    config.storage = :file
    config.enable_processing = false
    config.skip_ssrf_protection = true
  end
end
