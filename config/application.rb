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
    # Use cookies for session store
    config.middleware.use ActionDispatch::Cookies
    # `secure` at the store as well as via ssl_options in production: defence in depth, and it keeps the
    # attribute visible here rather than only as a side effect of force_ssl three files away. Gated on
    # the environment because an unconditional `secure: true` means the cookie is never sent over
    # http://localhost — development and the specs would silently stop being able to hold a session.
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
