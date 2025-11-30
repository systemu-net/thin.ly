require 'rails_helper'

RSpec.describe 'Api::V1::Users', type: :request do
  let(:user) { create(:user) }
  let(:auth_headers) { { 'Authorization' => "Bearer #{token}" } }
  let(:token) { Warden::JWTAuth::UserEncoder.new.call(user, :user, nil).first }

  describe 'GET /api/v1/user' do
    context 'when authenticated' do
      it 'returns the current user information' do
        get '/api/v1/user', headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['id']).to eq(user.id)
        expect(json['email']).to eq(user.email)
      end

      context 'when user has an avatar' do
        let(:user) { create(:user, :with_avatar) }

        it 'includes the avatar URL' do
          get '/api/v1/user', headers: auth_headers

          expect(response).to have_http_status(:ok)
          json = JSON.parse(response.body)
          expect(json['avatar_url']).to be_present
        end
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized' do
        get '/api/v1/user'

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PATCH /api/v1/user' do
    context 'when authenticated' do
      it 'updates user information' do
        patch '/api/v1/user',
              params: { user: { avatar: fixture_file_upload('test_avatar.jpg', 'image/jpeg') } },
              headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['avatar_url']).to be_present

        user.reload
        expect(user.avatar).to be_present
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized' do
        patch '/api/v1/user', params: { user: { avatar: 'test' } }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PATCH /api/v1/user/avatar' do
    let(:avatar_file) { fixture_file_upload('test_avatar.jpg', 'image/jpeg') }

    context 'when authenticated' do
      it 'uploads an avatar successfully' do
        patch '/api/v1/user/avatar',
              params: { avatar: avatar_file },
              headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['message']).to eq('Avatar uploaded successfully')
        expect(json['avatar_url']).to be_present

        user.reload
        expect(user.avatar).to be_present
      end

      it 'returns error when no file is provided' do
        patch '/api/v1/user/avatar',
              params: {},
              headers: auth_headers

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('No avatar file provided')
      end

      it 'replaces existing avatar' do
        user.update(avatar: fixture_file_upload('test_avatar.jpg', 'image/jpeg'))
        old_avatar_url = user.avatar.url

        patch '/api/v1/user/avatar',
              params: { avatar: fixture_file_upload('test_avatar2.jpg', 'image/jpeg') },
              headers: auth_headers

        expect(response).to have_http_status(:ok)
        user.reload
        expect(user.avatar.url).not_to eq(old_avatar_url)
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized' do
        patch '/api/v1/user/avatar',
              params: { avatar: avatar_file }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'DELETE /api/v1/user/avatar' do
    context 'when authenticated' do
      context 'when user has an avatar' do
        before do
          user.update(avatar: fixture_file_upload('test_avatar.jpg', 'image/jpeg'))
        end

        it 'removes the avatar successfully' do
          delete '/api/v1/user/avatar', headers: auth_headers

          expect(response).to have_http_status(:ok)
          json = JSON.parse(response.body)
          expect(json['message']).to eq('Avatar removed successfully')

          user.reload
          expect(user.avatar.url).to be_nil
        end
      end

      context 'when user has no avatar' do
        it 'returns error' do
          delete '/api/v1/user/avatar', headers: auth_headers

          expect(response).to have_http_status(:unprocessable_entity)
          json = JSON.parse(response.body)
          expect(json['error']).to eq('No avatar to remove')
        end
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized' do
        delete '/api/v1/user/avatar'

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
