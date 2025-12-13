# frozen_string_literal: true

# carrieewave testing
if Rails.env.test?
  CarrierWave.configure do |config|
    config.storage = :file
    config.enable_processing = false
    config.skip_ssrf_protection = true
  end
end

unless Rails.env.test?
  CarrierWave.configure do |config|
    config.fog_credentials = {
      provider: "AWS",
      aws_access_key_id: ENV["AWS_ACCESS_KEY_ID"] || Rails.application.credentials.dig(:aws_access_key_id),
      aws_secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"] || Rails.application.credentials.dig(:aws_secret_access_key),
      region: ENV["AWS_REGION"] || Rails.application.credentials.dig(:aws_region)
    }
    config.fog_use_ssl_for_aws = false
    config.storage = :fog
    config.fog_directory = ENV["S3_BUCKET"] || Rails.application.credentials.dig(:s3_bucket)
    config.fog_attributes = {
      "Cache-Control" => "max-age=#{365.days.to_i}",
      "Expires" => 1.year.from_now.httpdate
    }
  end
end
