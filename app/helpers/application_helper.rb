module ApplicationHelper
  # Base URL that published link-in-bio pages POST their analytics beacons to.
  # Production serves the API from the apex domain; development (and staging
  # tunnels) default to the ngrok tunnel, overridable via TRACKING_API_BASE.
  def tracking_api_base
    return "https://thin.ly" if Rails.env.production?

    ENV.fetch("TRACKING_API_BASE", "https://thinly.ngrok.app")
  end
end
