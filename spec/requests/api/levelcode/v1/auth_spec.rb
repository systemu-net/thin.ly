require 'rails_helper'

RSpec.describe 'Api::Levelcode::V1::Auth', type: :request do
  # The editor tokens are signed with a dedicated secret; set it for the suite.
  around do |example|
    prev = ENV['LEVELCODE_JWT_SECRET']
    ENV['LEVELCODE_JWT_SECRET'] = 'test-levelcode-secret'
    example.run
  ensure
    ENV['LEVELCODE_JWT_SECRET'] = prev
  end

  # One-time codes and the jti revocation denylist live in Redis, which the app
  # skips in test — give these specs an in-memory stand-in with real single-use
  # + set semantics.
  around { |example| with_fake_redis { example.run } }

  before do
    # The OAuth callback + one-time-code exchange create users through the
    # controller (not the factory), firing the real create_stripe_customer
    # callback — stub Stripe so these specs stay hermetic.
    allow(Stripe::Customer).to receive(:create).and_return(Stripe::Customer.construct_from(id: 'cus_test'))
    allow(Stripe::Customer).to receive(:retrieve).and_return(Stripe::Customer.construct_from(id: 'cus_test'))
  end

  let(:password) { 'password123' }
  let!(:user) { create(:user, email: 'editor@example.com', password: password) }
  let(:redirect_uri) { 'levelcode://levelcode.levelcode-ai/auth/callback' }

  def json
    JSON.parse(response.body)
  end

  describe 'POST /api/levelcode/v1/auth/login' do
    context 'with valid credentials and no redirect_uri (JSON)' do
      it 'returns access, refresh and profile' do
        post '/api/levelcode/v1/auth/login', params: { email: user.email, password: password }, as: :json

        expect(response).to have_http_status(:ok)
        expect(json['access']).to be_present
        expect(json['refresh']).to be_present
        expect(json.dig('profile', 'email')).to eq(user.email)
      end
    end

    context 'with a redirect_uri (browser, hardened code flow)' do
      it '302s to the callback carrying a one-time code' do
        post '/api/levelcode/v1/auth/login',
             params: { email: user.email, password: password, redirect_uri: redirect_uri, code_challenge: 'chal' }

        expect(response).to have_http_status(:found)
        location = URI.parse(response.headers['Location'])
        expect(location.scheme).to eq('levelcode')
        expect(Rack::Utils.parse_query(location.query)['code']).to be_present
      end
    end

    context 'even when token_fallback is requested (now removed for security)' do
      it 'still returns a one-time code and never raw tokens in the redirect URL' do
        post '/api/levelcode/v1/auth/login',
             params: { email: user.email, password: password, redirect_uri: redirect_uri, token_fallback: '1' }

        expect(response).to have_http_status(:found)
        q = Rack::Utils.parse_query(URI.parse(response.headers['Location']).query)
        expect(q['code']).to be_present
        expect(q['token']).to be_nil
        expect(q['refresh']).to be_nil
      end
    end

    it 'rejects bad credentials' do
      post '/api/levelcode/v1/auth/login', params: { email: user.email, password: 'wrong' }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json.dig('error', 'code')).to eq('invalid_credentials')
    end

    it 'refuses a non-https/non-editor redirect_uri (no open redirect)' do
      post '/api/levelcode/v1/auth/login',
           params: { email: user.email, password: password, redirect_uri: 'http://evil.example.com' }

      # Falls back to JSON rather than redirecting to an untrusted host.
      expect(response).to have_http_status(:ok)
      expect(json['access']).to be_present
    end
  end

  describe 'POST /api/levelcode/v1/auth/signup' do
    it 'creates a user and returns tokens' do
      expect {
        post '/api/levelcode/v1/auth/signup',
             params: { email: 'new@example.com', password: password, terms: true }, as: :json
      }.to change(User, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(json['access']).to be_present
    end

    it 'rejects signup without accepted terms' do
      post '/api/levelcode/v1/auth/signup',
           params: { email: 'noterms@example.com', password: password, terms: false }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig('error', 'code')).to eq('signup_failed')
    end
  end

  describe 'POST /api/levelcode/v1/auth/exchange (PKCE)' do
    let(:verifier) { 'a' * 64 }
    let(:challenge) do
      digest = Digest::SHA256.digest(verifier)
      Base64.urlsafe_encode64(digest, padding: false)
    end

    it 'redeems a valid code+verifier for tokens' do
      code = Levelcode::OneTimeCode.issue(user, challenge)

      post '/api/levelcode/v1/auth/exchange', params: { code: code, verifier: verifier }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json['access']).to be_present
      expect(json['refresh']).to be_present
      expect(json.dig('profile', 'email')).to eq(user.email)
    end

    it 'rejects a wrong verifier' do
      code = Levelcode::OneTimeCode.issue(user, challenge)

      post '/api/levelcode/v1/auth/exchange', params: { code: code, verifier: 'wrong' }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json.dig('error', 'code')).to eq('invalid_verifier')
    end

    it 'rejects an unknown code' do
      post '/api/levelcode/v1/auth/exchange', params: { code: 'nope', verifier: verifier }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json.dig('error', 'code')).to eq('invalid_code')
    end

    it 'is single-use' do
      code = Levelcode::OneTimeCode.issue(user, challenge)
      post '/api/levelcode/v1/auth/exchange', params: { code: code, verifier: verifier }, as: :json
      post '/api/levelcode/v1/auth/exchange', params: { code: code, verifier: verifier }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/levelcode/v1/auth/refresh' do
    it 'mints a new access token from a refresh token' do
      refresh = Levelcode::EditorToken.mint_refresh(user)

      post '/api/levelcode/v1/auth/refresh', params: { refresh: refresh }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json['access']).to be_present
    end

    it 'rejects an access token used as a refresh token (wrong scope)' do
      access = Levelcode::EditorToken.mint_access(user)

      post '/api/levelcode/v1/auth/refresh', params: { refresh: access }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/levelcode/v1/auth/signout' do
    it 'revokes the presented token jti' do
      access = Levelcode::EditorToken.mint_access(user)

      post '/api/levelcode/v1/auth/signout', headers: { 'Authorization' => "Bearer #{access}" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json['ok']).to eq(true)

      # The revoked token must now fail verification.
      expect {
        Levelcode::EditorToken.verify(access, scope: 'account:read')
      }.to raise_error(Levelcode::EditorToken::InvalidToken)
    end

    it 'requires authentication' do
      post '/api/levelcode/v1/auth/signout', as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/levelcode/v1/auth/web_handoff' do
    it 'mints a one-time browser sign-in URL that redeems to the same user' do
      access = Levelcode::EditorToken.mint_access(user)

      post '/api/levelcode/v1/auth/web_handoff', headers: { 'Authorization' => "Bearer #{access}" }, as: :json

      expect(response).to have_http_status(:ok)
      uri = URI.parse(json['url'])
      expect(uri.path).to eq('/ai/auth/handoff')
      code = Rack::Utils.parse_query(uri.query)['code']
      expect(code).to be_present
      # Single-use code, bound to this user (no PKCE — issued to an already-authed editor).
      expect(Levelcode::OneTimeCode.redeem(code)).to eq(user)
    end

    it 'requires a valid editor token' do
      post '/api/levelcode/v1/auth/web_handoff', as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # The public GET /auth/oauth was removed (unhardened token-minting redirect).
  # The site (levelcode.ai) performs the provider `authorize` step and calls this
  # service-token-authed mint endpoint with the provider `code`.
  describe 'POST /api/levelcode/v1/auth/callback (site -> backend mint)' do
    let(:svc) { 'test-service-token' }
    before { ENV['LEVELCODE_SITE_SERVICE_TOKEN'] = svc }
    after { ENV.delete('LEVELCODE_SITE_SERVICE_TOKEN') }

    it 'rejects a missing / invalid service token (403)' do
      post '/api/levelcode/v1/auth/callback', params: { provider: 'github', code: 'gh_code', mode: 'web' }
      expect(response).to have_http_status(:forbidden)
      expect(json.dig('error', 'code')).to eq('forbidden')
    end

    context 'github (server-side code exchange stubbed)' do
      before do
        token_res = instance_double(Net::HTTPOK, body: { access_token: 'gh_tok' }.to_json)
        allow(token_res).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        user_res = instance_double(Net::HTTPOK, body: { id: 42, login: 'octocat', name: 'Octo Cat', email: nil }.to_json)
        allow(user_res).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        emails_res = instance_double(Net::HTTPOK, body: [ { email: 'octo@example.com', primary: true, verified: true } ].to_json)
        allow(emails_res).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:use_ssl=)
        # perform_http now bounds every provider call (provider_oauth.rb: OPEN/READ/WRITE_TIMEOUT).
        # The double has to permit the setters or it rejects the very calls that stop a stalled
        # provider hanging the browser; the timeout VALUES are asserted in provider_oauth_spec.rb.
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:read_timeout=)
        allow(http).to receive(:write_timeout=)
        allow(http).to receive(:request) do |req|
          case req.path
          when '/login/oauth/access_token' then token_res
          when '/user/emails' then emails_res
          else user_res
          end
        end
      end

      it 'web mode: exchanges the code, creates the user, returns a web SESSION + profile (not the gateway access token)' do
        expect {
          post '/api/levelcode/v1/auth/callback',
               params: { provider: 'github', code: 'gh_code', redirect_uri: 'https://levelcode.ai/auth/callback', mode: 'web' },
               headers: { 'X-Levelcode-Service-Token' => svc }
        }.to change(User, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(json['session']).to be_present
        # Security: web sign-in must NOT hand out the editor's ai:* access token.
        expect(json['access']).to be_nil
        expect(json.dig('profile', 'email')).to eq('octo@example.com')
      end

      it 'editor mode: returns a one-time code, not tokens' do
        allow(Levelcode::OneTimeCode).to receive(:issue).and_return('one-time-code')

        post '/api/levelcode/v1/auth/callback',
             params: { provider: 'github', code: 'gh_code', mode: 'editor' },
             headers: { 'X-Levelcode-Service-Token' => svc }

        expect(response).to have_http_status(:ok)
        expect(json['code']).to eq('one-time-code')
        expect(json['access']).to be_nil
      end
    end

    it 'rejects an unknown provider' do
      post '/api/levelcode/v1/auth/callback',
           params: { provider: 'myspace' },
           headers: { 'X-Levelcode-Service-Token' => svc }
      expect(response).to have_http_status(:bad_request)
    end
  end
end
