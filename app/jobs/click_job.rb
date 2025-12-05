require "sidekiq"
require "rest-client"

class ClickJob
  include Sidekiq::Job
  queue_as :default

  def perform(lookup_code, ip_address, user_agent, referrer, source = nil)
    link = Link.find_by(lookup_code: lookup_code)
    click_attributes = {
      ip_address: ip_address,
      user_agent: user_agent,
      referrer: referrer,
      country: fetch_country(ip_address)
    }

    # Add source if it exists (e.g., 'qr' for QR code scans)
    click_attributes[:source] = source if source.present?

    link.clicks.create(click_attributes)
  end

  private

  def fetch_country(ip_address)
    response = RestClient.get("https://ipapi.co/#{ip_address}/json")
    JSON.parse(response.body)["country_name"]
  end
end
