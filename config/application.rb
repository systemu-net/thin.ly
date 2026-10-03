require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Backend
  class Application < Rails::Application
    # What ActionDispatch::SSL is given in production, where config/environments/production.rb turns
    # it on. Held here as a value so the specs can run the real middleware with the real options.
    #
    # redirect: false — the ALB already redirects http to https, and its health check reaches /up over
    # PLAIN HTTP and accepts only a 200 (.ebextensions/03_healthcheck.config). A redirect there marks
    # every instance unhealthy and takes the site down.
    #
    # hsts — deliberately short. A browser honours it for the full max-age and it cannot be withdrawn
    # early. Raise `expires` to 1.year once a week has passed clean, and only then consider
    # `subdomains: true`, which commits every present and future subdomain to HTTPS at once.
    SSL_OPTIONS = {
      redirect: false,
      hsts: { expires: 1.week, subdomains: false, preload: false }
    }.freeze

    # Use cookies for session store
    config.middleware.use ActionDispatch::Cookies
    # `secure` is set HERE, on the store, because nothing else will set it: with its redirect off,
    # ActionDispatch::SSL does not flag cookies Secure — Rails skips that for any request it would not
    # have redirected. Production only: unconditionally, the cookie would never be sent over
    # http://localhost, and neither development nor the specs could hold a session.
    #
    # same_site MUST STAY :lax. It is the Rails default, so it is stated explicitly to stop anyone
    # "hardening" it to :strict — the Google OAuth callback is a cross-site top-level GET, :strict
    # withholds the cookie on exactly that request, and the sign-in then dies with `session_expired`
    # because the `state` stashed in the session never comes back. See Levelcode::WebController.
    config.middleware.use ActionDispatch::Session::CookieStore,
                          key: "_your_app_session",
                          secure: Rails.env.production?,
                          same_site: :lax,
                          httponly: true

    config.api_only = true
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.2

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil
  end
end
