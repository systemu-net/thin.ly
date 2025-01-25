require "sidekiq"
require "rest-client"

class SimpleJob
  include Sidekiq::Job
  queue_as :default

  def perform(lookup_code, ip_address, user_agent, referrer)
    link = Link.find_by(lookup_code: lookup_code)
    link.clicks.create(
      ip_address: ip_address,
      user_agent: user_agent,
      referrer: referrer,
      country: fetch_country(ip_address)
    )
  end

  private

  def fetch_country(ip_address)
    response = RestClient.get("https://ipapi.co/#{ip_address}/json")
    JSON.parse(response.body)["country_name"]
  end
end
