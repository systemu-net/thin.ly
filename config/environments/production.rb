require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both threaded web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  # Ensures that a master key has been made available in ENV["RAILS_MASTER_KEY"], config/master.key, or an environment
  # key such as config/credentials/production.key. This key is used to decrypt credentials (and other encrypted files).
  # config.require_master_key = true

  # Disable serving static files from `public/`, relying on NGINX/Apache to do so instead.
  # config.public_file_server.enabled = false

  # Compress CSS using a preprocessor.
  # config.assets.css_compressor = :sass

  # Do not fall back to assets pipeline if a precompiled asset is missed.
  config.assets.compile = false

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = "X-Sendfile" # for Apache
  # config.action_dispatch.x_sendfile_header = "X-Accel-Redirect" # for NGINX

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Mount Action Cable outside main process or domain.
  # config.action_cable.mount_path = nil
  # config.action_cable.url = "wss://example.com/cable"
  # config.action_cable.allowed_request_origins = [ "http://example.com", /http:\/\/example.*/ ]

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # Can be used together with config.force_ssl for Strict-Transport-Security and secure cookies.
  config.assume_ssl = true

  # Strict-Transport-Security + secure cookies, WITHOUT the http->https redirect.
  #
  # `force_ssl` turns on ActionDispatch::SSL, which does three separate jobs: redirect, HSTS, and
  # flagging cookies `secure`. We want the last two and specifically NOT the first:
  #
  #   * The ALB already redirects — verified: http://thin.ly 301s and http://levelcode.ai 302s.
  #   * The ALB health check hits `/up` over PLAIN HTTP on the instance, and .ebextensions pins
  #     `MatcherHTTPCode: "200"`. A redirect there is a 301, every instance goes unhealthy, and the
  #     site is down. `assume_ssl` above should make the redirect unreachable anyway (it marks every
  #     request as SSL), but "should" is not a thing to bet an outage on, so the redirect is turned
  #     off explicitly rather than relied upon to never fire.
  #
  # Until now this was `force_ssl = false`, so the session cookie shipped WITHOUT `Secure` — it went
  # in cleartext on any plain-HTTP request — and no HSTS header was sent at all. Both verified on the
  # wire before this change.
  #
  # HSTS starts deliberately SHORT. A browser honours it for the full max-age and there is no way to
  # take it back early, so this is a week rather than the Rails default of a year. Once a week has
  # passed with no plain-HTTP breakage, raise `expires` to 1.year — and only then consider
  # `subdomains: true`, which would commit every present and future subdomain to HTTPS at once.
  config.force_ssl = true
  config.ssl_options = {
    redirect: false,
    secure_cookies: true,
    hsts: { expires: 1.week, subdomains: false, preload: false }
  }

  # Log to STDOUT by default
  config.logger = ActiveSupport::Logger.new(STDOUT)
    .tap  { |logger| logger.formatter = ::Logger::Formatter.new }
    .then { |logger| ActiveSupport::TaggedLogging.new(logger) }

  # Prepend all log lines with the following tags.
  config.log_tags = [ :request_id ]

  # "info" includes generic and useful information about system operation, but avoids logging too much
  # information to avoid inadvertent exposure of personally identifiable information (PII). If you
  # want to log everything, set the level to "debug".
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Use a different cache store in production.
  # config.cache_store = :mem_cache_store

  # Use a real queuing backend for Active Job (and separate queues per environment).
  # config.active_job.queue_adapter = :resque
  config.active_job.queue_adapter = :sidekiq
  # config.active_job.queue_name_prefix = "backend_production"

  # Disable caching for Action Mailer templates even if Action Controller
  # caching is enabled.
  config.action_mailer.perform_caching = false

  # ActionMailer configuration for production
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.smtp_settings = {
    address: "smtp.mailgun.org",
    port: 587,
    domain: "thin.ly",
    user_name: Rails.application.credentials.dig(:smtp_user_name),
    password: Rails.application.credentials.dig(:smtp_password),
    authentication: "plain",
    enable_starttls_auto: true,
    open_timeout: 5,
    read_timeout: 5
  }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # Allow requests to bypass host check for health checks and internal AWS traffic
  config.hosts = [
    /.*\.thin\.ly/, # Allow requests from subdomains like www.thin.ly
    "www.thin.ly",
    "thin.ly",
    "app.thin.ly",
    "levelcode.ai", # LevelCode Cloud account app (served at /ai/*)
    "www.levelcode.ai",
    ".elasticbeanstalk.com",
    /.*\.elasticbeanstalk\.com$/, # Allow all Elastic Beanstalk hosts
    /.*\.elb\.amazonaws\.com$/, # Allow ELB hostnames for health checks
    /.*\.compute-1\.amazonaws\.com$/, # Allow EC2 compute hostnames
    /^10\.\d+\.\d+\.\d+$/, # Allow AWS private network (10.0.0.0/8) for health checks
    /^34\.235\.33\.249$/, # Allow AWS ELB public IP
    /.*\.cloudfront\.net$/, # Allow CloudFront distributions
    "d2zf7dm8bk6c85.cloudfront.net" # Specific CloudFront distribution
  ]
  # Skip DNS rebinding protection for the health check endpoint
  # This allows ELB health checks to pass regardless of Host header
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }

  config.action_mailer.default_url_options = { host: "thin.ly" }
end
