source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "devise", "~> 5.0"
gem "devise-jwt", "~> 0.13.0"
gem "carrierwave", "~> 3.1"
gem "importmap-rails"
gem "jbuilder"
gem "pagy", "~> 9.3"
gem "figaro", "~> 1.3"
gem "fog-aws", "~> 3.33"
gem "mini_magick", "~> 5.3"
gem "puma", ">= 5.0"
gem "anthropic", "~> 1.55"
gem "aws-sdk-s3", "~> 1.226"
gem "rack-cors", "~> 3.0"
gem "rails", "~> 7.2.3"
gem "rest-client", "~> 2.1"
gem "rqrcode", "~> 3.2"
gem "ruby-openai", "~> 8.3.0"
gem "sidekiq", "~> 8.1"
gem "sprockets-rails"
gem "sqids", "~> 0.2.2"
gem "pg", "~> 1.6"
gem "stimulus-rails"
gem "stripe", "~> 13.5"
gem "turbo-rails"


# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

group :development, :test do
  gem "annotate", "~> 3.2"
  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", "~> 8.0", require: false
  gem "byebug", "~> 13.0"
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  gem "factory_bot_rails", "~> 6.5"

  gem "rails-controller-testing", "~> 1.0"
  gem "rspec-rails", "~> 8.0"
  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :test do
  gem "stripe-ruby-mock", "~> 5.0", require: "stripe_mock"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

gem "ostruct", "~> 0.6.3"

gem "octokit", "~> 10.0"

gem "googleauth", "~> 1.16"
gem "google-apis-safebrowsing_v4", "~> 0.21.0"
gem "json", "2.20.0"
gem "bigdecimal", "4.0.1"
gem "bcrypt", "3.1.21"

gem "sidekiq-cron", "~> 2.4"

gem "redis", "~> 5.4"
