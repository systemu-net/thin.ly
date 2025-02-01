require 'rails_helper'

RSpec.describe Shortener do
  let(:user) { create(:user) }
  let(:stripe_customer_id) { '1234' }

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: stripe_customer_id))
  end

  it 'shortens a URL to a 7 character lookup code' do
    url = 'https://www.example.com'
    shortener = Shortener.new(url, user.id).generate_short_link
    expect(shortener.lookup_code.length).to eq(7)
  end

  it 'gives each URL a unique lookup code' do
    url = "https://www.thin.ly/unique"
    shortener = Shortener.new(url, user.id).generate_short_link
    code1 = shortener.lookup_code
    url = "https://www.thin.ly/unique2"
    shortener = Shortener.new(url, user.id).generate_short_link
    code2 = shortener.lookup_code
    expect(code2).not_to eq(code1)
  end

  it 'always returns new unique code for the same URL' do
    url = "https://www.thin.ly/same"
    shortener = Shortener.new(url, user.id).generate_short_link
    code1 = shortener.lookup_code
    shortener = Shortener.new(url, user.id).generate_short_link
    code2 = shortener.lookup_code
    expect(code2).not_to eq(code1)
  end

  it 'generates a Link record with a unique lookup_code' do
    url = "https://www.thin.ly/unique"
    shortener = Shortener.new(url, user.id)
    link = shortener.generate_short_link
    expect(link.valid?).to eq(true)

    link2 = shortener.generate_short_link
    expect(link2.valid?).to eq(true)
  end
end
