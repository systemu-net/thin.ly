# == Schema Information
#
# Table name: qr_codes
#
#  id          :bigint           not null, primary key
#  image       :string
#  scans_count :integer          default(0), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  link_id     :bigint           not null
#  user_id     :bigint           not null
#
# Indexes
#
#  index_qr_codes_on_link_id  (link_id)
#  index_qr_codes_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (link_id => links.id)
#  fk_rails_...  (user_id => users.id)
#
require 'rails_helper'
require 'carrierwave/test/matchers'

RSpec.describe QrCode, type: :model do
  let(:user) { create(:user) }
  let(:link) { create(:link, user: user) }
  let(:qr_code) { create(:qr_code, user: user, link: link) }

  xit 'always has an image' do
    qr_code = QrCode.new(
      image: 'image',
      user_id: user.id,
      link_id: link.id
    )
    expect { qr_code.save }.to(change(QrCode, :count).by(1))
    expect(qr_code.valid?).to eq(true)
  end

  describe '#scans_count' do
    it 'returns 0 when there are no clicks' do
      expect(qr_code.scans_count).to eq(0)
    end

    it 'counts only clicks with source=qr' do
      # Create regular clicks (source=nil)
      create(:click, link: qr_code.link, source: nil)
      create(:click, link: qr_code.link, source: nil)

      # Create QR scans (source='qr')
      create(:click, link: qr_code.link, source: 'qr')
      create(:click, link: qr_code.link, source: 'qr')
      create(:click, link: qr_code.link, source: 'qr')

      qr_code.reload
      expect(qr_code.scans_count).to eq(3)
    end

    it 'returns 0 when link has no clicks with source=qr' do
      create(:click, link: qr_code.link, source: nil)
      create(:click, link: qr_code.link, source: nil)

      qr_code.reload
      expect(qr_code.scans_count).to eq(0)
    end

    it 'returns 0 when qr_code has no link' do
      qr_code.link = nil
      expect(qr_code.scans_count).to eq(0)
    end
  end
end
