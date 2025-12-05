require 'rails_helper'

RSpec.describe 'Api::V1::QrCodes', type: :request do
  let(:user) { create(:user) }
  let(:link) { create(:link, user: user) }
  let(:qr_code) { create(:qr_code, user: user, link: link) }

  describe 'GET /api/v1/qr_codes' do
    before do
      # Create multiple QR codes with different scan counts
      @qr1 = create(:qr_code, user: user, link: create(:link, user: user))
      @qr2 = create(:qr_code, user: user, link: create(:link, user: user))

      # Add QR scans (source='qr')
      create(:click, link: @qr1.link, source: 'qr')
      create(:click, link: @qr1.link, source: 'qr')

      # Add regular clicks (source=nil)
      create(:click, link: @qr1.link, source: nil)

      # Add one QR scan to second QR code
      create(:click, link: @qr2.link, source: 'qr')
    end

    it 'returns qr_codes with scans_count in link object' do
      get '/api/v1/qr_codes', headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      expect(json['qr_codes']).to be_an(Array)
      expect(json['qr_codes'].length).to eq(2)

      # Verify first QR code
      qr1_json = json['qr_codes'].find { |qr| qr['id'] == @qr1.id }
      expect(qr1_json['link']).to be_present
      expect(qr1_json['link']['lookup_code']).to eq(@qr1.link.lookup_code)
      expect(qr1_json['link']['original_url']).to eq(@qr1.link.original_url)
      expect(qr1_json['link']['scans_count']).to eq(2)

      # Verify second QR code
      qr2_json = json['qr_codes'].find { |qr| qr['id'] == @qr2.id }
      expect(qr2_json['link']).to be_present
      expect(qr2_json['link']['scans_count']).to eq(1)
    end

    it 'does not include regular clicks in scans_count' do
      get '/api/v1/qr_codes', headers: auth_headers(user)

      json = JSON.parse(response.body)
      qr1_json = json['qr_codes'].find { |qr| qr['id'] == @qr1.id }

      # Should only count the 2 QR scans, not the 1 regular click
      expect(qr1_json['link']['scans_count']).to eq(2)
    end
  end

  describe 'GET /api/v1/qr_codes/:id' do
    before do
      # Create QR scans
      create(:click, link: qr_code.link, source: 'qr')
      create(:click, link: qr_code.link, source: 'qr')
      create(:click, link: qr_code.link, source: 'qr')

      # Create regular clicks
      create(:click, link: qr_code.link, source: nil)
    end

    it 'returns qr_code with scans_count in link object' do
      get "/api/v1/qr_codes/#{qr_code.id}", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      expect(json['qr_code']).to be_present
      expect(json['qr_code']['id']).to eq(qr_code.id)
      expect(json['qr_code']['link']).to be_present
      expect(json['qr_code']['link']['lookup_code']).to eq(qr_code.link.lookup_code)
      expect(json['qr_code']['link']['scans_count']).to eq(3)
    end
  end

  describe 'POST /api/v1/qr_codes' do
    it 'creates a qr_code with scans_count of 0' do
      new_link = create(:link, user: user)

      post '/api/v1/qr_codes',
           params: { qr_code: { lookup_code: new_link.lookup_code } },
           headers: auth_headers(user)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)

      expect(json['qr_code']['link']['scans_count']).to eq(0)
      expect(json['qr_code']['link']['lookup_code']).to eq(new_link.lookup_code)
    end
  end
end
