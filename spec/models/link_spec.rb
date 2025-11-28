# == Schema Information
#
# Table name: links
#
#  id              :bigint           not null, primary key
#  description     :text
#  is_safe         :boolean
#  last_scanned_at :datetime
#  lookup_code     :string
#  original_url    :string
#  scan_failures   :integer          default(0)
#  title           :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_links_on_is_safe                      (is_safe)
#  index_links_on_is_safe_and_last_scanned_at  (is_safe,last_scanned_at)
#  index_links_on_last_scanned_at              (last_scanned_at)
#  index_links_on_user_id                      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require 'rails_helper'

RSpec.describe Link, type: :model do
  let(:user) { create(:user) }
  let(:stripe_customer_id) { '1234' }

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: stripe_customer_id))
  end

  it 'always has an original URL' do
    link = Link.new(
      original_url: 'https://www.thin.ly/example',
      lookup_code: "1234567",
      user_id: user.id
    )
    expect { link.save }.to(change(Link, :count).by(1))
    expect(link.valid?).to eq(true)
  end

  it 'is invalid if the URL is not formatted properly' do
    link = Link.new(
      original_url: 'thin.ly/example'
    )
    expect(link.valid?).to eq(false)
  end

  it 'lookup_code is always not empty' do
    link = Link.new(
      original_url: 'https://www.thin.ly/example',
      lookup_code: nil,
      user_id: user.id
    )
    expect(link.valid?).to eq(true)
  end

  it 'is invalid if it does not have a original_url' do
    link = Link.new(
      original_url: nil,
      lookup_code: "1234567"
    )
    expect(link.valid?).to eq(false)
  end

  it 'is always generating new unique lookup_code for each record' do
    link = Link.new(
      original_url: 'https://www.thin.ly/example',
      lookup_code: "1234567",
      user_id: user.id
    )
    link.save
    link2 = Link.new(
      original_url: 'https://www.thin.ly/link2',
      lookup_code: "1234567",
      user_id: user.id
    )
    expect { link2.save }.to(change(Link, :count).by(1))
  end

  it 'returns the original URL and associated user_id for a given short link' do
    link = Link.new(original_url: 'https://www.thin.ly/example', user_id: user.id)
    link.save

    expect(link.send(:find_by_lookup_code, link.lookup_code)).to eq(link)
  end

  it 'fails to find the original URL for a given short link and wrong user_id' do
    link = Link.new(original_url: 'https://www.thin.ly/example', user_id: user.id)
    link.save

    expect(link.send(:find_by_lookup_code, link.lookup_code)).to eq(link)
  end
end
