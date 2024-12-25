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
