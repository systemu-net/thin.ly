require 'rails_helper'

RSpec.describe ClickJob, type: :job do
  let(:user) { create(:user) }
  let(:link) { create(:link, user: user) }

  let(:lookup_code) { link.lookup_code }
  let(:ip_address) { '203.0.113.42' }
  let(:referrer) { 'https://twitter.com/link' }
  let(:source) { nil }

  let(:chrome_mac_ua) do
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.119 Safari/537.36'
  end

  let(:cloudfront_headers) do
    {
      'country' => 'US',
      'country_name' => 'United States',
      'city' => 'San Francisco',
      'region' => 'CA',
      'postal_code' => '94103',
      'latitude' => '37.7749',
      'longitude' => '-122.4194',
      'timezone' => 'America/Los_Angeles',
      'is_mobile' => false,
      'is_tablet' => false,
      'is_desktop' => true
    }
  end

  describe '#perform' do
    it 'creates a click record for the link' do
      expect {
        described_class.new.perform(lookup_code, ip_address, chrome_mac_ua, referrer, source, cloudfront_headers)
      }.to change(Click, :count).by(1)
    end

    it 'stores geolocation data from CloudFront headers' do
      described_class.new.perform(lookup_code, ip_address, chrome_mac_ua, referrer, source, cloudfront_headers)

      click = Click.last
      expect(click.country).to eq('US')
      expect(click.country_name).to eq('United States')
      expect(click.city).to eq('San Francisco')
      expect(click.region).to eq('CA')
      expect(click.postal_code).to eq('94103')
      expect(click.latitude.to_s).to start_with('37.77')
      expect(click.longitude.to_s).to start_with('-122.41')
      expect(click.timezone).to eq('America/Los_Angeles')
    end

    it 'stores device flags from CloudFront headers' do
      described_class.new.perform(lookup_code, ip_address, chrome_mac_ua, referrer, source, cloudfront_headers)

      click = Click.last
      expect(click.is_desktop).to be true
      expect(click.is_mobile).to be false
      expect(click.is_tablet).to be false
    end

    it 'stores parsed browser and OS info' do
      described_class.new.perform(lookup_code, ip_address, chrome_mac_ua, referrer, source, cloudfront_headers)

      click = Click.last
      expect(click.browser).to eq('Chrome')
      expect(click.browser_version).to eq('120.0')
      expect(click.os).to eq('macOS')
      expect(click.os_version).to eq('10.15.7')
    end

    it 'stores ip_address, user_agent, and referrer' do
      described_class.new.perform(lookup_code, ip_address, chrome_mac_ua, referrer, source, cloudfront_headers)

      click = Click.last
      expect(click.ip_address).to eq(ip_address)
      expect(click.user_agent).to eq(chrome_mac_ua)
      expect(click.referrer).to eq(referrer)
    end

    it 'stores source when provided' do
      described_class.new.perform(lookup_code, ip_address, chrome_mac_ua, referrer, 'qr', cloudfront_headers)

      expect(Click.last.source).to eq('qr')
    end

    it 'does nothing when link is not found' do
      expect {
        described_class.new.perform('INVALID', ip_address, chrome_mac_ua, referrer, source, cloudfront_headers)
      }.not_to change(Click, :count)
    end

    it 'defaults is_mobile and is_tablet to false when CloudFront headers are empty' do
      described_class.new.perform(lookup_code, ip_address, chrome_mac_ua, referrer, source, {})

      click = Click.last
      expect(click.is_mobile).to be false
      expect(click.is_tablet).to be false
      expect(click.is_desktop).to be false
    end
  end

  describe 'User-Agent parsing' do
    it 'detects Firefox browser' do
      ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0'
      described_class.new.perform(lookup_code, ip_address, ua, referrer, source, cloudfront_headers)

      click = Click.last
      expect(click.browser).to eq('Firefox')
      expect(click.browser_version).to eq('121.0')
    end

    it 'detects Edge browser' do
      ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Edg/120.0.2210.91'
      described_class.new.perform(lookup_code, ip_address, ua, referrer, source, cloudfront_headers)

      expect(Click.last.browser).to eq('Edge')
    end

    it 'detects Windows OS with version mapping' do
      ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0'
      described_class.new.perform(lookup_code, ip_address, ua, referrer, source, cloudfront_headers)

      expect(Click.last.os).to eq('Windows')
      expect(Click.last.os_version).to eq('10')
    end

    it 'detects iOS from iPhone UA' do
      ua = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15'
      described_class.new.perform(lookup_code, ip_address, ua, referrer, source, cloudfront_headers)

      expect(Click.last.os).to eq('iOS')
      expect(Click.last.os_version).to eq('17.2')
    end

    it 'detects Android OS' do
      ua = 'Mozilla/5.0 (Linux; Android 14.0; Pixel 8) AppleWebKit/537.36 Chrome/120.0'
      described_class.new.perform(lookup_code, ip_address, ua, referrer, source, cloudfront_headers)

      expect(Click.last.os).to eq('Android')
      expect(Click.last.os_version).to eq('14.0')
    end

    it 'returns Unknown for blank user_agent' do
      described_class.new.perform(lookup_code, ip_address, nil, referrer, source, cloudfront_headers)

      click = Click.last
      expect(click.browser).to eq('Unknown')
      expect(click.os).to eq('Unknown')
      expect(click.is_bot).to be false
    end
  end

  describe 'bot detection' do
    %w[Googlebot bingbot Slurp spider crawl Lighthouse HeadlessChrome].each do |bot_name|
      it "detects #{bot_name} as bot" do
        ua = "Mozilla/5.0 (compatible; #{bot_name}/2.1; +http://example.com/bot.html)"
        described_class.new.perform(lookup_code, ip_address, ua, referrer, source, cloudfront_headers)

        expect(Click.last.is_bot).to be true
      end
    end

    it 'does not flag regular browsers as bots' do
      described_class.new.perform(lookup_code, ip_address, chrome_mac_ua, referrer, source, cloudfront_headers)
      expect(Click.last.is_bot).to be false
    end
  end

  describe 'device type determination' do
    it 'returns "desktop" when CloudFront says desktop' do
      described_class.new.perform(lookup_code, ip_address, chrome_mac_ua, referrer, source, cloudfront_headers)
      expect(Click.last.device_type).to eq('desktop')
    end

    it 'returns "mobile" when CloudFront says mobile' do
      mobile_headers = cloudfront_headers.merge('is_mobile' => true, 'is_desktop' => false)
      described_class.new.perform(lookup_code, ip_address, chrome_mac_ua, referrer, source, mobile_headers)
      expect(Click.last.device_type).to eq('mobile')
    end

    it 'returns "tablet" when CloudFront says tablet' do
      tablet_headers = cloudfront_headers.merge('is_tablet' => true, 'is_desktop' => false)
      described_class.new.perform(lookup_code, ip_address, chrome_mac_ua, referrer, source, tablet_headers)
      expect(Click.last.device_type).to eq('tablet')
    end

    it 'returns "smarttv" when CloudFront says smarttv' do
      tv_headers = cloudfront_headers.merge('is_smarttv' => true, 'is_desktop' => false)
      described_class.new.perform(lookup_code, ip_address, chrome_mac_ua, referrer, source, tv_headers)
      expect(Click.last.device_type).to eq('smarttv')
    end

    it 'returns "bot" for bot user agents regardless of CloudFront headers' do
      bot_ua = 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)'
      described_class.new.perform(lookup_code, ip_address, bot_ua, referrer, source, cloudfront_headers)
      expect(Click.last.device_type).to eq('bot')
    end

    it 'returns "unknown" when no CloudFront headers and UA is not a bot' do
      described_class.new.perform(lookup_code, ip_address, chrome_mac_ua, referrer, source, {})
      expect(Click.last.device_type).to eq('unknown')
    end
  end
end
