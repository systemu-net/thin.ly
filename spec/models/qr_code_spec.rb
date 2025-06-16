# == Schema Information
#
# Table name: qr_codes
#
#  id         :bigint           not null, primary key
#  image      :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  link_id    :bigint           not null
#  user_id    :bigint           not null
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
  let(:qr_code) { create(:qr_code, user: user) }
  let(:link) { create(:link, user: user) }

  xit 'always has an image' do
    qr_code = QrCode.new(
      image: 'image',
      user_id: user.id,
      link_id: link.id
    )
    expect { qr_code.save }.to(change(QrCode, :count).by(1))
    expect(qr_code.valid?).to eq(true)
  end
end
