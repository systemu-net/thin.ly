# == Schema Information
#
# Table name: page_views
#
#  id              :bigint           not null, primary key
#  browser         :string
#  browser_version :string
#  city            :string
#  country         :string
#  device_type     :string
#  ip_address      :string
#  os              :string
#  os_version      :string
#  referrer        :string
#  region          :string
#  user_agent      :text
#  visited_at      :datetime         not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  brand_page_id   :bigint           not null
#
# Indexes
#
#  index_page_views_on_brand_page_id                 (brand_page_id)
#  index_page_views_on_brand_page_id_and_visited_at  (brand_page_id,visited_at)
#  index_page_views_on_country                       (country)
#  index_page_views_on_device_type                   (device_type)
#  index_page_views_on_visited_at                    (visited_at)
#
# Foreign Keys
#
#  fk_rails_...  (brand_page_id => brand_pages.id)
#
require 'rails_helper'

RSpec.describe PageView, type: :model do
  let(:user) { create(:user) }
  let(:brand_page) { create(:brand_page, user: user) }

  describe 'associations' do
    it 'belongs to brand_page' do
      page_view = build(:page_view)
      expect(page_view).to respond_to(:brand_page)
    end
  end

  describe 'validations' do
    it 'requires visited_at' do
      page_view = build(:page_view, visited_at: nil)
      expect(page_view).not_to be_valid
      expect(page_view.errors[:visited_at]).to include("can't be blank")
    end

    it 'requires brand_page' do
      page_view = build(:page_view, brand_page: nil)
      expect(page_view).not_to be_valid
      expect(page_view.errors[:brand_page]).to include("must exist")
    end
  end

  describe 'scopes' do
    let!(:page_view_today) { create(:page_view, brand_page: brand_page, visited_at: Time.current) }
    let!(:page_view_yesterday) { create(:page_view, brand_page: brand_page, visited_at: 1.day.ago) }
    let!(:page_view_last_week) { create(:page_view, brand_page: brand_page, visited_at: 1.week.ago) }
    let!(:page_view_last_month) { create(:page_view, brand_page: brand_page, visited_at: 1.month.ago) }

    describe '.recent' do
      it 'orders by visited_at descending' do
        expect(PageView.recent.first).to eq(page_view_today)
      end
    end

    describe '.today' do
      it 'returns only today\'s views' do
        expect(PageView.today).to include(page_view_today)
        expect(PageView.today).not_to include(page_view_yesterday, page_view_last_week, page_view_last_month)
      end
    end

    describe '.this_week' do
      it 'returns views from this week' do
        expect(PageView.this_week).to include(page_view_today, page_view_yesterday)
        expect(PageView.this_week).not_to include(page_view_last_week, page_view_last_month)
      end
    end

    describe '.this_month' do
      it 'returns views from this month' do
        expect(PageView.this_month).to include(page_view_today, page_view_yesterday)
        expect(PageView.this_month).not_to include(page_view_last_month)
      end
    end

    describe '.by_country' do
      let!(:us_view) { create(:page_view, brand_page: brand_page, country: 'US') }
      let!(:uk_view) { create(:page_view, brand_page: brand_page, country: 'UK') }

      it 'filters by country' do
        expect(PageView.by_country('US')).to include(us_view)
        expect(PageView.by_country('US')).not_to include(uk_view)
      end
    end

    describe '.by_device' do
      let!(:mobile_view) { create(:page_view, :mobile, brand_page: brand_page) }
      let!(:desktop_view) { create(:page_view, brand_page: brand_page, device_type: 'desktop') }

      it 'filters by device type' do
        expect(PageView.by_device('mobile')).to include(mobile_view)
        expect(PageView.by_device('mobile')).not_to include(desktop_view)
      end
    end
  end

  describe '.track_view' do
    let(:request_data) do
      {
        ip_address: '192.168.1.1',
        user_agent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
        referrer: 'https://www.google.com',
        country: 'US',
        city: 'New York',
        region: 'NY',
        browser: 'Chrome',
        browser_version: '141.0.0.0',
        os: 'macOS',
        os_version: '10.15.7',
        device_type: 'desktop',
        visited_at: Time.current
      }
    end

    it 'creates a page view with the provided data' do
      expect {
        PageView.track_view(brand_page, request_data)
      }.to change(PageView, :count).by(1)

      page_view = PageView.last
      expect(page_view.brand_page).to eq(brand_page)
      expect(page_view.ip_address).to eq('192.168.1.1')
      expect(page_view.country).to eq('US')
      expect(page_view.device_type).to eq('desktop')
    end

    it 'uses current time if visited_at is not provided' do
      request_data.delete(:visited_at)

      page_view = PageView.track_view(brand_page, request_data)
      expect(page_view.visited_at).to be_within(1.second).of(Time.current)
    end
  end
end
