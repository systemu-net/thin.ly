# == Schema Information
#
# Table name: clicks
#
#  id         :bigint           not null, primary key
#  country    :string
#  ip_address :string
#  referrer   :string
#  source     :string
#  user_agent :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  link_id    :bigint           not null
#
# Indexes
#
#  index_clicks_on_link_id  (link_id)
#  index_clicks_on_source   (source)
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
