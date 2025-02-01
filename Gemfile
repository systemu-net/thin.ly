source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "devise", "~> 4.9"
gem "devise-jwt", "~> 0.12.1"
gem "carrierwave", "~> 3.1"
gem "importmap-rails"
gem "jbuilder"
gem "figaro", "~> 1.2"
gem "fog-aws", "~> 3.30"
gem "puma", ">= 5.0"
gem "rack-cors", "~> 2.0"
gem "rails", "~> 7.2.2"
gem "rqrcode", "~> 2.2"
gem "sprockets-rails"
gem "sqids", "~> 0.2.1"
gem "sqlite3", ">= 2.5.0"
gem "stimulus-rails"
gem "stripe", "~> 13.4"
gem "turbo-rails"


# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

group :development, :test do
  gem "annotate", "~> 3.2"
  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false
  gem "byebug", "~> 11.1"
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  gem "factory_bot_rails", "~> 6.4"

  gem "rails-controller-testing", "~> 1.0"
  gem "rspec-rails", "~> 7.1"
  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

gem "sidekiq", "~> 7.3"

gem "rest-client", "~> 2.1"
