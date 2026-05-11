require 'rails_helper'

RSpec.describe 'Google Auth', type: :request do
  describe 'POST /users/auth/google' do
    let(:google_sub) { '109876543210987654321' }
    let(:google_email) { 'google-user@example.com' }
    let(:id_token) { 'fake.id.token' }
    let(:payload) do
      {
        'sub' => google_sub,
        'email' => google_email,
        'email_verified' => true,
        'name' => 'Test User'
      }
    end

    before do
      allow(Stripe::Customer).to receive(:create).and_return(double(id: 'cus_test'))
    end

    context 'with a valid Google id_token' do
      before do
        allow(Google::Auth::IDTokens).to receive(:verify_oidc).and_return(payload)
      end

      it 'creates a new user and returns a JWT in the Authorization header' do
        expect {
          post '/users/auth/google',
               params: { id_token: id_token, terms_accepted: true },
               as: :json
        }.to change(User, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(response.headers['Authorization']).to be_present
        expect(response.headers['Authorization']).to start_with('Bearer ')

        body = JSON.parse(response.body)
        expect(body.dig('user', 'email')).to eq(google_email)

        user = User.find_by(email: google_email)
        expect(user.provider).to eq('google_oauth2')
        expect(user.uid).to eq(google_sub)
      end

      it 'records the terms acceptance audit fields on a new Google user' do
        post '/users/auth/google',
             params: { id_token: id_token, terms_accepted: true },
             as: :json

        user = User.find_by(email: google_email)
        expect(user.terms_accepted).to be true
        expect(user.terms_accepted_at).to be_present
        expect(user.terms_accepted_version).to eq(User::TERMS_VERSION)
      end

      it 'signs in an existing google-linked user without creating a new one' do
        create(:user, email: google_email, provider: 'google_oauth2', uid: google_sub)

        expect {
          post '/users/auth/google', params: { id_token: id_token }, as: :json
        }.not_to change(User, :count)

        expect(response).to have_http_status(:ok)
        expect(response.headers['Authorization']).to be_present
      end

      it 'links an existing email-only user to the google account' do
        existing = create(:user, email: google_email)
        expect(existing.provider).to be_nil

        expect {
          post '/users/auth/google', params: { id_token: id_token }, as: :json
        }.not_to change(User, :count)

        existing.reload
        expect(existing.provider).to eq('google_oauth2')
        expect(existing.uid).to eq(google_sub)
      end

      it 'rejects new signups when terms_accepted is missing' do
        expect {
          post '/users/auth/google', params: { id_token: id_token }, as: :json
        }.not_to change(User, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include('must be accepted')
      end
    end

    context 'when Google rejects the id_token' do
      before do
        allow(Google::Auth::IDTokens).to receive(:verify_oidc)
          .and_raise(Google::Auth::IDTokens::SignatureError.new('bad signature'))
      end

      it 'returns 401' do
        post '/users/auth/google',
             params: { id_token: id_token, terms_accepted: true },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when Google reports the email is not verified' do
      before do
        allow(Google::Auth::IDTokens).to receive(:verify_oidc)
          .and_return(payload.merge('email_verified' => false))
      end

      it 'refuses to create a user' do
        expect {
          post '/users/auth/google',
               params: { id_token: id_token, terms_accepted: true },
               as: :json
        }.not_to change(User, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'when id_token is missing' do
      it 'returns 401' do
        post '/users/auth/google', params: {}, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
