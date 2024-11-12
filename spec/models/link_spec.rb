require 'rails_helper'

RSpec.describe Link, type: :model do
  it 'always has an original URL' do
    link = Link.new(
      original_url: 'https://www.thin.ly/example',
      lookup_code: "1234567"
    )
    expect { link.save }.to(change(Link, :count).by(1))
    expect(link.valid?).to eq(true)
  end

  it 'lookup_code is always not empty' do
    link = Link.new(
      original_url: 'https://www.thin.ly/example',
      lookup_code: nil
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
      lookup_code: "1234567"
    )
    link.save
    link2 = Link.new(
      original_url: 'https://www.thin.ly/link2',
      lookup_code: "1234567"
    )
    expect { link2.save }.to(change(Link, :count).by(1))
  end
end
