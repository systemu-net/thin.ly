require 'rails_helper'

RSpec.describe Shortener do
  it 'shortens a URL to a 7 character lookup code' do
    url = 'https://www.example.com'
    shortener = Shortener.new(url)
    expect(shortener.lookup_code.length).to eq(7)
  end

  it 'gives each URL a unique lookup code' do
  end
end
