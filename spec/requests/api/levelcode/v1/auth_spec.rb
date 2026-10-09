require 'rails_helper'

RSpec.describe 'Api::Levelcode::V1::Auth', type: :request do
  # travel_to — token expiry is a function of the clock, and these examples move it rather than
  # minting pre-expired tokens, so they exercise the same code path a real expiry takes.
  include ActiveSupport::Testing::TimeHelpers

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

  # A server that has been told nothing: the shipped editor schemes only, whatever the machine
  # running the suite has exported (LEVELCODE_EXTRA_EDITOR_SCHEMES). Examples that opt in say so.
  before { with_extra_editor_schemes('') }

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

    # WHICH addresses are the editor's, at this controller's own gate (it keeps its own copy of the
    # rule Levelcode::WebController has). Anything else falls back to JSON: no redirect, no code.
    {
      'levelcode://levelcode.levelcode-ai/auth/callback' => 'the shipped editor',
      'atom-plus-plus://levelcode.levelcode-ai/auth/callback' => 'a build from before the rename'
    }.each do |address, whose|
      it "302s the code to #{whose} — #{address}" do
        post '/api/levelcode/v1/auth/login',
             params: { email: user.email, password: password, redirect_uri: "#{address}?windowId=2", code_challenge: 'chal' }

        expect(response).to have_http_status(:found)
        location = response.headers['Location']
        expect(location).to start_with("#{address}?windowId=2&code=")
        expect(Rack::Utils.parse_query(URI.parse(location).query)['code']).to be_present
      end
    end

    {
      'levelcode-dev://levelcode.levelcode-ai/auth/callback' => 'a scheme that is not on the list',
      'levelcode://evil.example/auth/callback' => 'the right scheme on another host',
      'levelcode://levelcode.levelcode-ai/elsewhere' => 'the right host on another path'
    }.each do |address, what|
      it "does not redirect to #{what} — #{address}" do
        post '/api/levelcode/v1/auth/login',
             params: { email: user.email, password: password, redirect_uri: address, code_challenge: 'chal' }

        expect(response).to have_http_status(:ok)
        expect(response.headers['Location']).to be_nil
        expect(json['access']).to be_present
      end
    end

    it '302s the code to a development editor once the server is told to take its scheme' do
      with_extra_editor_schemes('levelcode-dev')

      post '/api/levelcode/v1/auth/login',
           params: { email: user.email, password: password, code_challenge: 'chal',
                     redirect_uri: 'levelcode-dev://levelcode.levelcode-ai/auth/callback?windowId=2' }

      expect(response).to have_http_status(:found)
      location = response.headers['Location']
      expect(location).to start_with('levelcode-dev://levelcode.levelcode-ai/auth/callback?windowId=2&code=')
      expect(Rack::Utils.parse_query(URI.parse(location).query)['code']).to be_present
    end

    it 'refuses a non-https/non-editor redirect_uri (no open redirect)' do
      post '/api/levelcode/v1/auth/login',
           params: { email: user.email, password: password, redirect_uri: 'http://evil.example.com' }

      # Falls back to JSON rather than redirecting to an untrusted host.
      expect(response).to have_http_status(:ok)
      expect(json['access']).to be_present
    end

    # The web edition of the editor: this gate asks the same rule as the /ai flows do, so a page the
    # one takes is a page the other takes, and the one it refuses it refuses.
    context 'on a server told of a web editor (LEVELCODE_WEB_EDITOR_ORIGINS)' do
      let(:web_callback) do
        'https://editor.levelcode.test/callback.html?vscode-reqid=1&vscode-scheme=levelcode' \
          '&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback'
      end

      before { with_web_editor('https://editor.levelcode.test') }

      it '302s the code to the editor\'s page, with the callback as the editor built it' do
        post '/api/levelcode/v1/auth/login',
             params: { email: user.email, password: password, redirect_uri: web_callback, code_challenge: 'chal' }

        expect(response).to have_http_status(:found)
        location = response.headers['Location']
        expect(location).to start_with("#{web_callback}&code=")
        expect(Rack::Utils.parse_query(URI.parse(location).query)['code']).to be_present
      end

      it 'binds the code to the challenge it was sent with: the page must hold the verifier' do
        post '/api/levelcode/v1/auth/login',
             params: { email: user.email, password: password, redirect_uri: web_callback, code_challenge: 'chal' }
        code = Rack::Utils.parse_query(URI.parse(response.headers['Location']).query)['code']

        expect { Levelcode::OneTimeCode.redeem(code, 'not-the-verifier') }.to raise_error(Levelcode::OneTimeCode::InvalidVerifier)
      end

      it 'puts its own code over one the address came with' do
        post '/api/levelcode/v1/auth/login',
             params: { email: user.email, password: password, redirect_uri: "#{web_callback}&code=attacker", code_challenge: 'chal' }

        expect(response).to have_http_status(:found)
        q = Rack::Utils.parse_query(URI.parse(response.headers['Location']).query)
        expect(q['code']).to be_present
        expect(q['code']).not_to eq('attacker')
      end

      {
        'an origin that is not on the list' => 'https://evil.test/callback.html?vscode-reqid=1&vscode-scheme=levelcode&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback',
        'credentials that make the listed host another' => 'https://editor.levelcode.test@evil.test/callback.html?vscode-reqid=1&vscode-scheme=levelcode&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback',
        'the listed origin over http' => 'http://editor.levelcode.test/callback.html?vscode-reqid=1&vscode-scheme=levelcode&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback',
        'another page of the listed origin' => 'https://editor.levelcode.test/index.html?vscode-reqid=1&vscode-scheme=levelcode&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback',
        'a page told to hand the code to another extension' => 'https://editor.levelcode.test/callback.html?vscode-reqid=1&vscode-scheme=vscode&vscode-authority=vscode.github-authentication&vscode-path=%2Fdid-authenticate',
        'a page whose vscode-query names the code' => 'https://editor.levelcode.test/callback.html?vscode-reqid=1&vscode-scheme=levelcode&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback&vscode-query=code%3Dattacker'
      }.each do |what, address|
        it "does not redirect to #{what}" do
          post '/api/levelcode/v1/auth/login',
               params: { email: user.email, password: password, redirect_uri: address, code_challenge: 'chal' }

          expect(response).to have_http_status(:ok)
          expect(response.headers['Location']).to be_nil
          expect(json['access']).to be_present
        end
      end

      it 'goes on redirecting to the desktop editor' do
        post '/api/levelcode/v1/auth/login',
             params: { email: user.email, password: password, redirect_uri: "#{redirect_uri}?windowId=2", code_challenge: 'chal' }

        expect(response.headers['Location']).to start_with("#{redirect_uri}?windowId=2&code=")
      end
    end

    # Production, until the web editor ships.
    it 'does not redirect to the web editor\'s page on a server that has not been told of one' do
      post '/api/levelcode/v1/auth/login',
           params: { email: user.email, password: password, code_challenge: 'chal',
                     redirect_uri: 'https://editor.levelcode.test/callback.html?vscode-reqid=1&vscode-scheme=levelcode' \
                                   '&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback' }

      expect(response).to have_http_status(:ok)
      expect(response.headers['Location']).to be_nil
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

    it 'ROTATES the refresh token — a new one, with a later expiry, so the 30 days run from last use' do
      refresh = Levelcode::EditorToken.mint_refresh(user)
      old_claims = Levelcode::EditorToken.verify(refresh, scope: 'refresh')

      travel_to(10.days.from_now) do
        post '/api/levelcode/v1/auth/refresh', params: { refresh: refresh }, as: :json
      end

      expect(response).to have_http_status(:ok)
      expect(json['refresh']).to be_present
      expect(json['refresh']).not_to eq(refresh)
      new_claims = Levelcode::EditorToken.verify(json['refresh'], scope: 'refresh')
      expect(new_claims['jti']).not_to eq(old_claims['jti'])
      expect(new_claims['exp']).to be > old_claims['exp']
      expect(new_claims['exp'] - old_claims['exp']).to be_within(60).of(10.days.to_i)
    end

    it 'keeps the previous refresh token usable (rotation is a sliding window, not revocation)' do
      refresh = Levelcode::EditorToken.mint_refresh(user)
      post '/api/levelcode/v1/auth/refresh', params: { refresh: refresh }, as: :json
      expect(response).to have_http_status(:ok)

      post '/api/levelcode/v1/auth/refresh', params: { refresh: refresh }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it 'answers refresh_expired, in plain words, for a refresh token past its 30 days' do
      refresh = Levelcode::EditorToken.mint_refresh(user)

      travel_to(31.days.from_now) do
        post '/api/levelcode/v1/auth/refresh', params: { refresh: refresh }, as: :json
      end

      expect(response).to have_http_status(:unauthorized)
      expect(json.dig('error', 'code')).to eq('refresh_expired')
      expect(json.dig('error', 'message')).to eq(Levelcode::EditorToken::EXPIRED_MESSAGE)
      expect(response.body).not_to include('Signature')
    end

    it 'still answers invalid_refresh for a refresh token that is broken rather than expired' do
      post '/api/levelcode/v1/auth/refresh', params: { refresh: 'not.a.token' }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json.dig('error', 'code')).to eq('invalid_refresh')
    end
  end

  describe 'an expired ACCESS token at a bearer endpoint' do
    it 'answers token_expired with a sentence, never the JWT library text' do
      access = Levelcode::EditorToken.mint_access(user)

      travel_to(9.hours.from_now) do
        post '/api/levelcode/v1/auth/web_handoff', headers: { 'Authorization' => "Bearer #{access}" }, as: :json
      end

      expect(response).to have_http_status(:unauthorized)
      expect(json.dig('error', 'code')).to eq('token_expired')
      expect(json.dig('error', 'message')).to eq(Levelcode::EditorToken::EXPIRED_MESSAGE)
      expect(response.body).not_to include('Signature has expired')
    end

    it 'keeps the generic unauthorized code for a token that is invalid rather than expired' do
      post '/api/levelcode/v1/auth/web_handoff', headers: { 'Authorization' => 'Bearer not.a.token' }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json.dig('error', 'code')).to eq('unauthorized')
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
        allow(Net::HTTP).to receive(:start) { |*, &session| session.call(http) }
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
