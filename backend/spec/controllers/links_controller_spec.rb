require 'rails_helper'

RSpec.describe Api::V1::LinksController, type: :controller do
  let(:url) { 'https://www.thin.ly' }
  let(:valid_attributes) { { original_url: url } }

  it 'can shorten a link provided by the user' do
    post :create, params: { link: valid_attributes }, as: :json

    link = assigns(:link)
    expect(link.original_url).to eq(url)
    expect(link.valid?).to eq(true)
    expect(link.persisted?).to eq(true)
    expect(link.lookup_code.length).to eq(7)

    expect(response).to have_http_status(:created)
    expect(response).to render_template("create")
  end
end
