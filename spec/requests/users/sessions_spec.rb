require 'rails_helper'

RSpec.describe 'User Sessions', type: :request do
  let(:password) { 'password123' }
  let!(:user) { create(:user, password: password) }

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: 'cus_test'))
  end

  def decoded_jwt(response)
    auth = response.headers['Authorization']
    raise 'no Authorization header' unless auth&.start_with?('Bearer ')

    secret = ENV['SECRET_KEY_BASE'] || Rails.application.credentials.fetch(:secret_key_base)
    JWT.decode(auth.split(' ').last, secret, true, algorithm: 'HS256').first
  end

  describe 'POST /users/sign_in' do
    it 'returns a JWT that expires in ~24 hours when remember_me is absent' do
      post '/users/sign_in',
           params: { user: { email: user.email, password: password } },
           as: :json

      expect(response).to have_http_status(:ok)
      payload = decoded_jwt(response)
      lifetime = payload['exp'] - payload['iat']
      expect(lifetime).to be_within(60).of(24.hours.to_i)
      expect(payload['jti']).to eq(user.jti)
    end

    it 'returns a JWT that expires in ~6 months when remember_me is true' do
      post '/users/sign_in',
           params: { user: { email: user.email, password: password, remember_me: true } },
           as: :json

      expect(response).to have_http_status(:ok)
      payload = decoded_jwt(response)
      lifetime = payload['exp'] - payload['iat']
      expect(lifetime).to be_within(60).of(6.months.to_i)
    end

    it 'returns a 24-hour JWT when remember_me is explicitly false' do
      post '/users/sign_in',
           params: { user: { email: user.email, password: password, remember_me: false } },
           as: :json

      payload = decoded_jwt(response)
      lifetime = payload['exp'] - payload['iat']
      expect(lifetime).to be_within(60).of(24.hours.to_i)
    end

    it 'uses the user’s current jti so sign-out can still revoke the token' do
      post '/users/sign_in',
           params: { user: { email: user.email, password: password, remember_me: true } },
           as: :json

      payload = decoded_jwt(response)
      expect(payload['jti']).to eq(user.jti)
    end
  end
end
