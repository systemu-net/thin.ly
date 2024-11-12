require 'rails_helper'

RSpec.describe LinksController, type: :controller do
  let(:url) { 'https://www.thin.ly' }
  let(:headers) do
    {
      'ACCEPT' => 'application/json',
      'CONTENT_TYPE' => 'application/json'
    }
  end

  it 'can shorten a link provided by the user' do
    request.env['HTTP_ACCEPT'] = headers['ACCEPT']
    request.env['CONTENT_TYPE'] = headers['CONTENT_TYPE']

    post :create, params: { link: { original_url: url } }

    link = assigns(:link)
    expect(link.original_url).to eq(url)
    expect(link.valid?).to eq(true)
    expect(link.persisted?).to eq(true)
    expect(link.lookup_code.length).to eq(7)

    expect(response).to have_http_status(:created)
    expect(response_body['original_url']).to eq(url)
  end
end
