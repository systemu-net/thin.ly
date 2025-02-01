require 'rails_helper'

RSpec.describe Api::V1::LinksController, type: :controller do
  let(:url) { 'https://www.thin.ly' }
  let(:valid_attributes) { { original_url: url } }
  let(:user) { create(:user) }
  let(:stripe_customer_id) { '1234' }

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: stripe_customer_id))
  end

  it 'can shorten a link provided by the user' do
    sign_in(user)
    post :create, params: { link: valid_attributes }, as: :json

    link = assigns(:link)
    expect(link.original_url).to eq(url)
    expect(link.valid?).to eq(true)
    expect(link.persisted?).to eq(true)
    expect(link.lookup_code.length).to eq(7)
    expect(link.user_id).to eq(user.id)

    expect(response).to have_http_status(:created)
    expect(response).to render_template("create")
  end
end
