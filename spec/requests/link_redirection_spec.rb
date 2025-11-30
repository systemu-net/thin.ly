require 'rails_helper'

RSpec.describe "Link Redirection", type: :request do
  let(:user) { create(:user) }
  let(:stripe_customer_id) { '1234' }

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: stripe_customer_id))
  end

  it 'redirects to the original URL for a given short link' do
    url = 'https://www.thin.ly'
    shortener = Shortener.new(url, user.id)
    link = shortener.generate_short_link

    get link.shortened_url
    expect(response).to redirect_to(link.original_url)
  end

  it 'redirects to link not found page for a short link that does not exist' do
    get "/1234567"
    expect(response).to have_http_status(:found)
    expect(response).to redirect_to(link_not_found_path)
  end
end
