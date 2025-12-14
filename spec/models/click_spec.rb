# == Schema Information
#
# Table name: clicks
#
#  id              :bigint           not null, primary key
#  browser         :string
#  browser_version :string
#  city            :string
#  country         :string
#  country_name    :string
#  device_type     :string
#  ip_address      :string
#  is_bot          :boolean          default(FALSE)
#  is_desktop      :boolean          default(FALSE)
#  is_mobile       :boolean          default(FALSE)
#  is_tablet       :boolean          default(FALSE)
#  latitude        :decimal(10, 6)
#  longitude       :decimal(10, 6)
#  os              :string
#  os_version      :string
#  postal_code     :string
#  referrer        :string
#  region          :string
#  source          :string
#  timezone        :string
#  user_agent      :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  link_id         :bigint           not null
#
# Indexes
#
#  index_clicks_on_city                (city)
#  index_clicks_on_country_name        (country_name)
#  index_clicks_on_device_and_created  (device_type,created_at)
#  index_clicks_on_device_type         (device_type)
#  index_clicks_on_is_bot              (is_bot)
#  index_clicks_on_is_mobile           (is_mobile)
#  index_clicks_on_link_and_created    (link_id,created_at)
#  index_clicks_on_link_id             (link_id)
#  index_clicks_on_region              (region)
#  index_clicks_on_source              (source)
#
# Foreign Keys
#
#  fk_rails_...  (link_id => links.id)
#
require 'rails_helper'

RSpec.describe Click, type: :model do
  let(:user) { create(:user) }
  let(:link) { create(:link, user: user) }
  let(:qr_code) { create(:qr_code, user: user, link: link) }

  describe 'counter cache callbacks' do
    it 'increments qr_code scans_count when creating a QR scan' do
      expect {
        create(:click, link: link, source: 'qr')
      }.to change { qr_code.reload.scans_count }.by(1)
    end

    it 'does not increment scans_count for regular clicks' do
      expect {
        create(:click, link: link, source: nil)
      }.not_to change { qr_code.reload.scans_count }
    end

    it 'decrements qr_code scans_count when destroying a QR scan' do
      click = create(:click, link: link, source: 'qr')
      qr_code.reload

      expect {
        click.destroy
      }.to change { qr_code.reload.scans_count }.by(-1)
    end

    it 'increments link clicks_count for all clicks' do
      expect {
        create(:click, link: link, source: 'qr')
      }.to change { link.reload.clicks_count }.by(1)

      expect {
        create(:click, link: link, source: nil)
      }.to change { link.reload.clicks_count }.by(1)
    end
  end
end
