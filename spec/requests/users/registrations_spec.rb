require 'rails_helper'

RSpec.describe 'User Registrations', type: :request do
  describe 'POST /users' do
    before do
      # Prevent real Stripe calls during registration
      allow(Stripe::Customer).to receive(:create).and_return(double(id: 'cus_test'))
    end

    it 'rejects signup when terms_accepted is false or missing' do
      payloads = [
        { user: { email: 'no-terms@example.com', password: 'password123' } },
        { user: { email: 'false-terms@example.com', password: 'password123', terms_accepted: false } }
      ]

      payloads.each do |payload|
        expect {
          post '/users', params: payload, as: :json
        }.not_to change(User, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include('must be accepted')
      end
    end

    it 'creates a user when terms_accepted is true and persists it' do
      email = 'accepted-terms@example.com'

      expect {
        post '/users', params: { user: { email: email, password: 'password123', terms_accepted: true } }, as: :json
      }.to change(User, :count).by(1)

      expect(response).to have_http_status(:created)

      user = User.find_by(email: email)
      expect(user).to be_present
      expect(user.terms_accepted).to eq(true)
    end
  end
end
