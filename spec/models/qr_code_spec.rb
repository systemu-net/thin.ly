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

  it 'validates presence of image' do
    qr_code = QrCode.new(user_id: user.id, link_id: link.id, image: nil)
    expect(qr_code).not_to be_valid
    expect(qr_code.errors[:image]).to include("can't be blank")
  end

  it 'validates uniqueness of user_id scoped to link_id' do
    create(:qr_code, user: user, link: link)
    duplicate = build(:qr_code, user: user, link: link)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:user_id]).to include('has already been taken')
  end

  describe 'associations' do
    it 'belongs to a link' do
      assoc = described_class.reflect_on_association(:link)
      expect(assoc.macro).to eq(:belongs_to)
    end

    it 'belongs to a user' do
      assoc = described_class.reflect_on_association(:user)
      expect(assoc.macro).to eq(:belongs_to)
    end

    it 'has many api_requests' do
      assoc = described_class.reflect_on_association(:api_requests)
      expect(assoc.macro).to eq(:has_many)
    end

    it 'has many resources' do
      assoc = described_class.reflect_on_association(:resources)
      expect(assoc.macro).to eq(:has_many)
    end

    it 'has many brand_pages through resources' do
      assoc = described_class.reflect_on_association(:brand_pages)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:through]).to eq(:resources)
    end
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
