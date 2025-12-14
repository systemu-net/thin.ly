json.analytics do
  # Date range
  json.date_range do
    json.start_date params[:start_date] || 30.days.ago.to_date.to_s
    json.end_date params[:end_date] || Date.today.to_s
  end

  # Summary statistics
  json.summary do
    json.total_clicks @total_clicks
    json.human_clicks @human_clicks
    json.bot_clicks @bot_clicks
    json.qr_scans @qr_scans
    json.direct_clicks @direct_clicks
  end

  # Device breakdown
  json.devices do
    json.mobile @device_stats[:mobile]
    json.desktop @device_stats[:desktop]
    json.tablet @device_stats[:tablet]
  end

  # Top cities (with region and country)
  json.top_cities @top_cities do |location|
    json.city location[:city]
    json.region location[:region]
    json.country location[:country]
    json.clicks location[:clicks]
  end

  # Country breakdown
  json.countries @countries do |country_data|
    json.country country_data[:country]
    json.clicks country_data[:clicks]
  end

  # Browser breakdown
  json.browsers @browsers do |browser_data|
    json.browser browser_data[:browser]
    json.clicks browser_data[:clicks]
  end

  # Operating system breakdown
  json.operating_systems @operating_systems do |os_data|
    json.os os_data[:os]
    json.clicks os_data[:clicks]
  end

  # Time series data (daily clicks)
  json.daily_clicks @daily_clicks do |day_data|
    json.date day_data[:date]
    json.clicks day_data[:clicks]
  end

  # Recent clicks with details
  json.recent_clicks @recent_clicks do |click|
    json.id click.id
    json.city click.city
    json.region click.region
    json.country click.country_name
    json.device_type click.device_type
    json.browser click.browser
    json.os click.os
    json.is_bot click.is_bot
    json.source click.source
    json.created_at click.created_at
  end
end
