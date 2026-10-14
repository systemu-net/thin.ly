require 'rails_helper'

# LevelCode Cloud account app server surface (Levelcode::WebController, mounted at /ai/*)
# + the StaticController brand switch. The account PAGES are the onetime SPA; this
# controller owns the JSON auth/session/billing flows the SPA delegates to.
# EmailCode / OneTimeCode / ProviderOAuth / Stripe are stubbed.
RSpec.describe 'Levelcode::Web (SPA backend at /ai/*)', type: :request do
  around do |example|
    prev = ENV['LEVELCODE_JWT_SECRET']
    ENV['LEVELCODE_JWT_SECRET'] = 'test-levelcode-secret'
    example.run
  ensure
    ENV['LEVELCODE_JWT_SECRET'] = prev
  end

  # User creation calls Stripe (before_validation :create_stripe_customer); stub it.
  before do
    allow(Stripe::Customer).to receive(:create).and_return(Stripe::Customer.construct_from(id: 'cus_test'))
    allow(Stripe::Customer).to receive(:retrieve).and_return(Stripe::Customer.construct_from(id: 'cus_test'))
    host! 'www.example.com'
  end

  # A server that has been told nothing: the shipped editor schemes only. Said outright, so the
  # machine running the suite cannot say otherwise — a developer may well have
  # LEVELCODE_EXTRA_EDITOR_SCHEMES exported for their own server. Examples that opt in say so.
  before { with_extra_editor_schemes('') }

  let(:editor_uri) { 'levelcode://levelcode.levelcode-ai/auth/callback' }
  def json = JSON.parse(response.body)

  describe 'brand switch (StaticController#ui)' do
    it 'serves the levelcode shell for /ai paths on a LevelCode host' do
      host! 'levelcode.ai' # strict isolation: the account shell only renders on a LevelCode host
      get '/ai/login'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('LevelCode Cloud')
      expect(response.body).to include('id="root"')
      # (csrf_meta_tags renders only when forgery protection is on — off in test env.)
    end

    it 'bounces /ai on the thin.ly host to the canonical LevelCode origin' do
      get '/ai/login' # default host www.example.com (a non-LevelCode host)
      expect(response).to redirect_to('https://levelcode.ai/ai/login')
    end

    it 'redirects a bare path on an levelcode host into /ai' do
      host! 'levelcode.ai'
      get '/pricing'
      expect(response).to redirect_to('/ai/pricing')
    end
  end

  describe 'POST /ai/auth/email' do
    it 'issues + emails a code and returns JSON' do
      allow(Levelcode::EmailCode).to receive(:issue).with('user@example.com').and_return('123456')
      mail = instance_double(ActionMailer::MessageDelivery, deliver_now: true)
      allow(LevelcodeAuthMailer).to receive(:login_code).with('user@example.com', '123456').and_return(mail)

      post '/ai/auth/email', params: { email: 'user@example.com' }

      expect(response).to have_http_status(:ok)
      expect(json).to eq('sent' => true)
      expect(LevelcodeAuthMailer).to have_received(:login_code).with('user@example.com', '123456')
    end

    it 'rejects an invalid address with a JSON error' do
      post '/ai/auth/email', params: { email: 'not-an-email' }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig('error', 'code')).to eq('invalid_email')
    end
  end

  describe 'POST /ai/auth/verify' do
    it 'web mode: signs in and returns { redirect: /ai/account }' do
      allow(Levelcode::EmailCode).to receive(:verify).and_return(true)

      expect {
        post '/ai/auth/verify', params: { email: 'web@example.com', code: '123456' }
      }.to change(User, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(json).to eq('redirect' => '/ai/account')

      # Session persists — the account API now authenticates via the cookie.
      get '/api/levelcode/v1/account/profile'
      expect(response).to have_http_status(:ok)
    end

    context 'signup attribution (first-touch, stamped on the NEW user only)' do
      before { allow(Levelcode::EmailCode).to receive(:verify).and_return(true) }

      let(:attribution) do
        { source: 'linkedin', params: { linkedin: 'saienkoanastasia' },
          landing: '/ai?linkedin=saienkoanastasia', referrer: 'https://lnkd.in/x',
          ts: '2026-07-22T19:35:41.166Z' }
      end

      it 'stamps a sanitized attribution on a newly created account' do
        post '/ai/auth/verify', params: { email: 'lead@example.com', code: '123456', attribution: attribution }, as: :json
        expect(response).to have_http_status(:ok)

        attr = User.find_by(email: 'lead@example.com').signup_attribution
        expect(attr['source']).to eq('linkedin')
        expect(attr['params']).to eq('linkedin' => 'saienkoanastasia')
        expect(attr['landing']).to eq('/ai?linkedin=saienkoanastasia')
        expect(attr['recorded_at']).to be_present # server timestamp, not client-controlled
      end

      it 'does NOT overwrite an existing account (acquisition attribution, not last-touch)' do
        existing = User.create!(email: 'known@example.com', password: 'password123', terms_accepted: true)
        expect(existing.signup_attribution).to be_nil

        post '/ai/auth/verify', params: { email: 'known@example.com', code: '123456', attribution: attribution }, as: :json
        expect(response).to have_http_status(:ok)
        expect(existing.reload.signup_attribution).to be_nil
      end

      it 'stays null on an organic sign-in (no campaign params)' do
        post '/ai/auth/verify', params: { email: 'organic@example.com', code: '123456' }, as: :json
        expect(User.find_by(email: 'organic@example.com').signup_attribution).to be_nil
      end

      it 'survives a concurrent-signup race (unique-violation → re-find, never a 500)' do
        # A parallel request already created this email; our find_by missed it, so our INSERT loses to the
        # DB unique index. The rescue must re-find the winner and sign them in cleanly.
        winner = User.create!(email: 'race@example.com', password: 'password123', terms_accepted: true)
        allow(User).to receive(:find_by).and_call_original
        allow(User).to receive(:find_by).with(email: 'race@example.com').and_return(nil, winner)
        allow(User).to receive(:create).and_raise(ActiveRecord::RecordNotUnique)

        post '/ai/auth/verify', params: { email: 'race@example.com', code: '123456' }, as: :json

        expect(response).to have_http_status(:ok)
        expect(json).to eq('redirect' => '/ai/account')
      end

      # Length clamping alone let CR/LF through, and these values are later
      # interpolated into the signup notification's Subject header.
      it 'strips control characters so nothing header-unsafe is ever stored' do
        nasty = { source: "linkedin\r\nBcc: attacker@example.com",
                  params: { linkedin: "anastasia\nX-Injected: yes" },
                  landing: "/ai\r\n" }
        post '/ai/auth/verify', params: { email: 'nasty@example.com', code: '123456', attribution: nasty }, as: :json

        attr = User.find_by(email: 'nasty@example.com').signup_attribution
        [ attr['source'], attr['params']['linkedin'], attr['landing'] ].each do |v|
          expect(v).not_to include("\r")
          expect(v).not_to include("\n")
        end
        expect(attr['source']).to start_with('linkedin')
        expect(attr['params']['linkedin']).to start_with('anastasia')
      end

      it 'whitelists keys and bounds sizes — never trusts the client blob' do
        hostile = { source: 'x' * 200,
                    params: { linkedin: 'a' * 500, evil: 'ignored', utm_source: 'newsletter' },
                    landing: 'y' * 1000 }
        post '/ai/auth/verify', params: { email: 'hostile@example.com', code: '123456', attribution: hostile }, as: :json

        attr = User.find_by(email: 'hostile@example.com').signup_attribution
        expect(attr['source'].length).to eq(40) # truncated
        expect(attr['params']).to eq('linkedin' => 'a' * 120, 'utm_source' => 'newsletter') # unknown 'evil' dropped
        expect(attr['landing'].length).to eq(300)
      end
    end

    it 'editor mode: returns { redirect: deep-link?code= } bound to the PKCE challenge' do
      allow(Levelcode::EmailCode).to receive(:verify).and_return(true)
      allow(Levelcode::OneTimeCode).to receive(:issue).and_return('one-time-code')

      post '/ai/auth/verify',
           params: { email: 'editor@example.com', code: '123456', redirect_uri: editor_uri, code_challenge: 'chal' }

      expect(response).to have_http_status(:ok)
      loc = URI.parse(json['redirect'])
      expect(loc.scheme).to eq('levelcode')
      expect(Rack::Utils.parse_query(loc.query)['code']).to eq('one-time-code')
    end

    it 'editor mode: preserves ?windowId on the deep-link (VS Code asExternalUri)' do
      allow(Levelcode::EmailCode).to receive(:verify).and_return(true)
      allow(Levelcode::OneTimeCode).to receive(:issue).and_return('one-time-code')

      post '/ai/auth/verify',
           params: { email: 'win@example.com', code: '123456',
                     redirect_uri: "#{editor_uri}?windowId=1", code_challenge: 'chal' }

      expect(response).to have_http_status(:ok)
      q = Rack::Utils.parse_query(URI.parse(json['redirect']).query)
      expect(q['windowId']).to eq('1')
      expect(q['code']).to eq('one-time-code')
    end

    it 'editor mode: decodes a double-encoded deep-link redirect_uri (the reported sign-in bug)' do
      allow(Levelcode::EmailCode).to receive(:verify).and_return(true)
      allow(Levelcode::OneTimeCode).to receive(:issue).and_return('one-time-code')

      # As it arrives after one Rack decode: the ?windowId tail is still %3F/%3D-encoded.
      post '/ai/auth/verify',
           params: { email: 'enc@example.com', code: '123456',
                     redirect_uri: "#{editor_uri}%3FwindowId%3D1", code_challenge: 'chal' }

      expect(response).to have_http_status(:ok)
      loc = URI.parse(json['redirect'])
      expect(loc.scheme).to eq('levelcode')
      q = Rack::Utils.parse_query(loc.query)
      expect(q['windowId']).to eq('1')
      expect(q['code']).to eq('one-time-code')
    end

    it 'fails closed for an editor deep-link with no code_challenge (no unbound code)' do
      allow(Levelcode::EmailCode).to receive(:verify).and_return(true)
      expect(Levelcode::OneTimeCode).not_to receive(:issue)

      post '/ai/auth/verify', params: { email: 'nc@example.com', code: '123456', redirect_uri: editor_uri }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig('error', 'code')).to eq('link_expired')
    end

    it 'treats a same-host https redirect_uri as web (no open-redirect code handoff)' do
      allow(Levelcode::EmailCode).to receive(:verify).and_return(true)
      expect(Levelcode::OneTimeCode).not_to receive(:issue)

      post '/ai/auth/verify',
           params: { email: 'sh@example.com', code: '123456', redirect_uri: 'https://www.example.com/AbCdEfg' }

      expect(response).to have_http_status(:ok)
      expect(json).to eq('redirect' => '/ai/account')
    end

    # An address that is not the editor's is not refused here — it is not an editor sign-in at all.
    # The browser is signed in to the web account and sent to it, and the editor that asked hears
    # nothing. That is what a developer sees when their editor's scheme is not one this server takes.
    it 'treats an editor-shaped address on a scheme it does not take as a web sign-in' do
      allow(Levelcode::EmailCode).to receive(:verify).and_return(true)
      expect(Levelcode::OneTimeCode).not_to receive(:issue)

      post '/ai/auth/verify',
           params: { email: 'dev@example.com', code: '123456',
                     redirect_uri: 'levelcode-dev://levelcode.levelcode-ai/auth/callback', code_challenge: 'chal' }

      expect(response).to have_http_status(:ok)
      expect(json).to eq('redirect' => '/ai/account')
    end

    # …and on a server told to take it, the same request is an editor sign-in.
    it 'hands a development editor its code once the server is told to take its scheme' do
      with_extra_editor_schemes('levelcode-dev')
      allow(Levelcode::EmailCode).to receive(:verify).and_return(true)
      allow(Levelcode::OneTimeCode).to receive(:issue).and_return('one-time-code')

      # Double-encoded, as the editor's ?windowId tail arrives through the login page.
      post '/ai/auth/verify',
           params: { email: 'dev@example.com', code: '123456',
                     redirect_uri: 'levelcode-dev://levelcode.levelcode-ai/auth/callback%3FwindowId%3D1', code_challenge: 'chal' }

      expect(response).to have_http_status(:ok)
      expect(json).to eq('redirect' => 'levelcode-dev://levelcode.levelcode-ai/auth/callback?windowId=1&code=one-time-code')
    end

    it 'still fails closed for a development editor with no code_challenge' do
      with_extra_editor_schemes('levelcode-dev')
      allow(Levelcode::EmailCode).to receive(:verify).and_return(true)
      expect(Levelcode::OneTimeCode).not_to receive(:issue)

      post '/ai/auth/verify',
           params: { email: 'dev@example.com', code: '123456', redirect_uri: 'levelcode-dev://levelcode.levelcode-ai/auth/callback' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig('error', 'code')).to eq('link_expired')
    end

    # The web edition of the editor: a page on an origin of its own. Its callback is that page's
    # /callback.html, carrying the deep link it stands for in the vscode-* parameters. The code goes to
    # the page, which hands it to the extension that asked.
    context 'on a server told of a web editor (LEVELCODE_WEB_EDITOR_ORIGINS)' do
      let(:web_origin) { 'https://editor.levelcode.test' }
      # As the editor's own code builds it: asExternalUri(levelcode://levelcode.levelcode-ai/auth/callback).
      let(:web_callback) do
        "#{web_origin}/callback.html?vscode-reqid=1&vscode-scheme=levelcode" \
          '&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback'
      end

      before do
        with_web_editor(web_origin)
        allow(Levelcode::EmailCode).to receive(:verify).and_return(true)
        allow(Levelcode::OneTimeCode).to receive(:issue).and_return('one-time-code')
      end

      it 'hands the code to the page, bound to the PKCE challenge, with the callback as the editor built it' do
        post '/ai/auth/verify',
             params: { email: 'web-editor@example.com', code: '123456', redirect_uri: web_callback, code_challenge: 'chal' }

        expect(response).to have_http_status(:ok)
        expect(json).to eq('redirect' => "#{web_callback}&code=one-time-code")
        expect(Levelcode::OneTimeCode).to have_received(:issue).with(User.find_by(email: 'web-editor@example.com'), 'chal')
      end

      it 'does the same when the callback arrives encoded once more, as it does through the login page' do
        post '/ai/auth/verify',
             params: { email: 'enc-web@example.com', code: '123456', redirect_uri: CGI.escape(web_callback), code_challenge: 'chal' }

        expect(response).to have_http_status(:ok)
        expect(json).to eq('redirect' => "#{web_callback}&code=one-time-code")
      end

      # What the extension actually sends: vscode.Uri#toString() has percent-encoded the query as one
      # component (`=` and `&` and the `%` of the encoded path with it), and the hops through the login
      # page and the provider add their own. The gate decodes until stable, and hands the page the
      # callback as it built it.
      it 'takes the callback in the form the extension sends it — its query encoded as a whole' do
        as_sent = "#{web_origin}/callback.html?" + ERB::Util.url_encode(
          'vscode-reqid=1&vscode-scheme=levelcode&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback'
        )
        expect(as_sent).to include('vscode-reqid%3D1%26vscode-scheme%3Dlevelcode', 'vscode-path%3D%252Fauth%252Fcallback')

        post '/ai/auth/verify',
             params: { email: 'as-sent@example.com', code: '123456', redirect_uri: as_sent, code_challenge: 'chal' }

        expect(response).to have_http_status(:ok)
        expect(json).to eq('redirect' => "#{web_callback}&code=one-time-code")
      end

      # The whole of it, through both controllers and a real one-time code: the page that asked gets a
      # code it can exchange — with the verifier it holds, and not without.
      it 'is a whole sign-in: the code the page is handed is redeemed with its verifier, and only with it' do
        allow(Levelcode::OneTimeCode).to receive(:issue).and_call_original
        verifier = 'v' * 43
        challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)

        with_fake_redis do
          2.times do |attempt|
            post '/ai/auth/verify',
                 params: { email: "whole-#{attempt}@example.com", code: '123456', redirect_uri: web_callback, code_challenge: challenge }
            code = Rack::Utils.parse_query(URI.parse(json['redirect']).query)['code']
            expect(code).to be_present

            post '/api/levelcode/v1/auth/exchange',
                 params: { code: code, verifier: attempt.zero? ? verifier : 'not-the-verifier' }.to_json,
                 headers: { 'CONTENT_TYPE' => 'application/json' }

            if attempt.zero?
              expect(response).to have_http_status(:ok)
              expect(json['access']).to be_present
              expect(json['refresh']).to be_present
              expect(json.dig('profile', 'email')).to eq('whole-0@example.com')
            else
              expect(response).to have_http_status(:unauthorized)
              expect(json.dig('error', 'code')).to eq('invalid_verifier')
            end
          end
        end
      end

      it 'keeps the request id and every parameter the page asked with — only the code is added' do
        asked = "#{web_origin}/callback.html?vscode-reqid=42&vscode-scheme=atom-plus-plus" \
                '&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback&vscode-query=windowId%3D3'
        post '/ai/auth/verify',
             params: { email: 'keep@example.com', code: '123456', redirect_uri: asked, code_challenge: 'chal' }

        q = Rack::Utils.parse_query(URI.parse(json['redirect']).query)
        expect(q).to eq('vscode-reqid' => '42', 'vscode-scheme' => 'atom-plus-plus',
                        'vscode-authority' => 'levelcode.levelcode-ai', 'vscode-path' => '/auth/callback',
                        'vscode-query' => 'windowId=3', 'code' => 'one-time-code')
      end

      it 'puts its own code over one the address came with' do
        post '/ai/auth/verify',
             params: { email: 'over@example.com', code: '123456', redirect_uri: "#{web_callback}&code=attacker", code_challenge: 'chal' }

        q = Rack::Utils.parse_query(URI.parse(json['redirect']).query)
        expect(q['code']).to eq('one-time-code')
        expect(json['redirect']).not_to include('attacker')
      end

      it 'still fails closed with no code_challenge' do
        expect(Levelcode::OneTimeCode).not_to receive(:issue)

        post '/ai/auth/verify', params: { email: 'nc-web@example.com', code: '123456', redirect_uri: web_callback }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig('error', 'code')).to eq('link_expired')
      end

      it 'still hands a desktop editor its own code' do
        post '/ai/auth/verify',
             params: { email: 'desk@example.com', code: '123456', redirect_uri: editor_uri, code_challenge: 'chal' }

        expect(json).to eq('redirect' => "#{editor_uri}?code=one-time-code")
      end

      # Not refused: not an editor sign-in at all. The browser is signed in to the web account and sent
      # to it, and nothing is minted for anywhere else.
      {
        'an origin the server was not told of' =>
          'https://evil.test/callback.html?vscode-reqid=1&vscode-scheme=levelcode&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback',
        'the listed host with credentials that make it another' =>
          'https://editor.levelcode.test@evil.test/callback.html?vscode-reqid=1&vscode-scheme=levelcode&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback',
        'a look-alike host' =>
          'https://editor.levelcode.test.evil.test/callback.html?vscode-reqid=1&vscode-scheme=levelcode&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback',
        'the listed origin over http' =>
          'http://editor.levelcode.test/callback.html?vscode-reqid=1&vscode-scheme=levelcode&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback',
        'another page of the listed origin' =>
          'https://editor.levelcode.test/index.html?vscode-reqid=1&vscode-scheme=levelcode&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback',
        'a page told to hand the code to another extension' =>
          'https://editor.levelcode.test/callback.html?vscode-reqid=1&vscode-scheme=vscode&vscode-authority=vscode.github-authentication&vscode-path=%2Fdid-authenticate',
        'a page told twice' =>
          'https://editor.levelcode.test/callback.html?vscode-reqid=1&vscode-scheme=levelcode&vscode-authority=vscode.github-authentication&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback',
        'a page whose vscode-query names the code' =>
          'https://editor.levelcode.test/callback.html?vscode-reqid=1&vscode-scheme=levelcode&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback&vscode-query=code%3Dattacker',
        'a page whose vscode-query names the code, encoded past what is decoded for it' =>
          'https://editor.levelcode.test/callback.html?vscode-reqid=1&vscode-scheme=levelcode&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback&vscode-query=%2525252563ode%25252523%25252561ttacker',
        'the page with a fragment' =>
          'https://editor.levelcode.test/callback.html?vscode-reqid=1&vscode-scheme=levelcode&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback#x'
      }.each do |what, address|
        it "signs in to the web account and mints nothing for #{what}" do
          expect(Levelcode::OneTimeCode).not_to receive(:issue)

          post '/ai/auth/verify',
               params: { email: 'refused-web@example.com', code: '123456', redirect_uri: address, code_challenge: 'chal' }

          expect(response).to have_http_status(:ok)
          expect(json).to eq('redirect' => '/ai/account')
        end
      end
    end

    # The extension host runs on an origin of its own per session and calls the API from there; CORS lets
    # it in. It is never where a code is sent: nothing it names is a callback.
    context 'on a server told of the web editor\'s extension host (LEVELCODE_WEB_EXTENSION_HOST_ORIGINS)' do
      let(:vscode_query) do
        'vscode-reqid=1&vscode-scheme=levelcode&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback'
      end

      before do
        with_web_editor('https://editor.levelcode.test',
                        extension_hosts: 'https://*.ext.levelcode.test, https://ext.levelcode.test, http://*.localhost:8801')
        allow(Levelcode::EmailCode).to receive(:verify).and_return(true)
        allow(Levelcode::OneTimeCode).to receive(:issue).and_return('one-time-code')
      end

      it 'still hands the code to the editor\'s own page' do
        post '/ai/auth/verify',
             params: { email: 'host-a@example.com', code: '123456', code_challenge: 'chal',
                       redirect_uri: "https://editor.levelcode.test/callback.html?#{vscode_query}" }

        expect(json['redirect']).to eq("https://editor.levelcode.test/callback.html?#{vscode_query}&code=one-time-code")
      end

      {
        'a session of the extension host' => 'https://v--abc123.ext.levelcode.test',
        'the extension host\'s domain, named exactly' => 'https://ext.levelcode.test',
        'a local development session of it' => 'http://v--abc.localhost:8801'
      }.each do |what, base|
        it "signs in to the web account and mints nothing for the callback page on #{what}" do
          expect(Levelcode::OneTimeCode).not_to receive(:issue)

          post '/ai/auth/verify',
               params: { email: 'host-b@example.com', code: '123456', code_challenge: 'chal',
                         redirect_uri: "#{base}/callback.html?#{vscode_query}" }

          expect(response).to have_http_status(:ok)
          expect(json).to eq('redirect' => '/ai/account')
        end
      end
    end

    # Production, until the web editor ships: the page's own address is no editor's.
    it 'treats the web editor\'s callback as a web sign-in on a server that has not been told of one' do
      allow(Levelcode::EmailCode).to receive(:verify).and_return(true)
      expect(Levelcode::OneTimeCode).not_to receive(:issue)

      post '/ai/auth/verify',
           params: { email: 'off@example.com', code: '123456', code_challenge: 'chal',
                     redirect_uri: 'https://editor.levelcode.test/callback.html?vscode-reqid=1&vscode-scheme=levelcode' \
                                   '&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback' }

      expect(response).to have_http_status(:ok)
      expect(json).to eq('redirect' => '/ai/account')
    end

    it 'rejects an invalid code' do
      allow(Levelcode::EmailCode).to receive(:verify).and_return(false)
      post '/ai/auth/verify', params: { email: 'nope@example.com', code: '000000' }
      expect(response).to have_http_status(:unauthorized)
      expect(json.dig('error', 'code')).to eq('invalid_code')
    end
  end

  describe 'OAuth' do
    it 'GET /ai/auth/oauth/github 302s to the provider authorize URL' do
      allow(Levelcode::ProviderOAuth).to receive(:authorize_url).and_return('https://github.test/authorize?state=x')
      get '/ai/auth/oauth/github'
      expect(response).to redirect_to('https://github.test/authorize?state=x')
    end

    it 'GET /ai/auth/callback rejects a mismatched state' do
      get '/ai/auth/callback', params: { code: 'gh', state: 'forged' }
      expect(response).to redirect_to('/ai/login?error=session_expired')
    end

    it 'GET /ai/auth/callback (valid state, web) signs in and 302s to /ai/account' do
      allow(SecureRandom).to receive(:urlsafe_base64).and_return('teststate')
      allow(Levelcode::ProviderOAuth).to receive(:authorize_url).and_return('https://github.test/authorize')
      allow(Levelcode::ProviderOAuth).to receive(:github_user).and_return(User.create!(email: 'gh@example.com', password: 'x' * 20, terms_accepted: true))

      get '/ai/auth/oauth/github' # stashes session state = teststate
      get '/ai/auth/callback', params: { code: 'gh', state: 'teststate' }

      expect(response).to redirect_to('/ai/account')
    end

    # Google rides the SAME oauth_start/oauth_callback path as GitHub (the callback dispatches on the
    # STASHED provider, so it calls google_user). This locks in the Google branch the new "Continue with
    # Google" login button depends on.
    it 'GET /ai/auth/oauth/google 302s to the provider authorize URL' do
      allow(Levelcode::ProviderOAuth).to receive(:authorize_url).and_return('https://google.test/authorize?state=x')
      get '/ai/auth/oauth/google'
      expect(response).to redirect_to('https://google.test/authorize?state=x')
    end

    it 'GET /ai/auth/callback (valid state, google, web) signs in and 302s to /ai/account' do
      allow(SecureRandom).to receive(:urlsafe_base64).and_return('teststate')
      allow(Levelcode::ProviderOAuth).to receive(:authorize_url).and_return('https://google.test/authorize')
      allow(Levelcode::ProviderOAuth).to receive(:google_user).and_return(User.create!(email: 'g@example.com', password: 'x' * 20, terms_accepted: true))

      get '/ai/auth/oauth/google' # stashes session state = teststate + provider = google
      get '/ai/auth/callback', params: { code: 'ggl', state: 'teststate' }

      expect(response).to redirect_to('/ai/account')
    end

    context 'for a web editor (LEVELCODE_WEB_EDITOR_ORIGINS)' do
      let(:web_callback) do
        'https://editor.levelcode.test/callback.html?vscode-reqid=3&vscode-scheme=levelcode' \
          '&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback'
      end

      before do
        with_web_editor('https://editor.levelcode.test')
        allow(SecureRandom).to receive(:urlsafe_base64).and_return('teststate')
        allow(Levelcode::ProviderOAuth).to receive(:authorize_url).and_return('https://github.test/authorize')
        allow(Levelcode::ProviderOAuth).to receive(:github_user)
          .and_return(User.create!(email: 'gh-web@example.com', password: 'x' * 20, terms_accepted: true))
      end

      it 'carries the page through the provider round trip, and hands the code to it' do
        allow(Levelcode::OneTimeCode).to receive(:issue).and_return('one-time-code')

        get '/ai/auth/oauth/github', params: { redirect_uri: web_callback, code_challenge: 'chal' }
        get '/ai/auth/callback', params: { code: 'gh', state: 'teststate' }

        expect(response).to redirect_to("#{web_callback}&code=one-time-code")
        expect(Levelcode::OneTimeCode).to have_received(:issue).with(User.find_by(email: 'gh-web@example.com'), 'chal')
      end

      it 'does not carry an address that is not the page — the sign-in ends on the web account' do
        expect(Levelcode::OneTimeCode).not_to receive(:issue)

        get '/ai/auth/oauth/github',
            params: { redirect_uri: web_callback.sub('editor.levelcode.test', 'evil.test'), code_challenge: 'chal' }
        get '/ai/auth/callback', params: { code: 'gh', state: 'teststate' }

        expect(response).to redirect_to('/ai/account')
      end
    end

    it 'GET /ai/auth/oauth/twitter is rejected (only github/google are allowed)' do
      get '/ai/auth/oauth/twitter'
      expect(response).to redirect_to('/ai/login')
    end

    # Marketing attribution across the OAuth round-trip. Before this, ONLY the email
    # flow recorded a channel, so every GitHub/Google signup was attributed to
    # nothing — which silently undercounts whichever channel sends developers.
    describe 'marketing attribution' do
      let(:attribution) do
        { source: 'linkedin', params: { linkedin: 'anastasia' }, landing: '/ai' }.to_json
      end

      def start_oauth_with_attribution(blob = attribution)
        allow(SecureRandom).to receive(:urlsafe_base64).and_return('teststate')
        allow(Levelcode::ProviderOAuth).to receive(:authorize_url).and_return('https://github.test/authorize')
        get '/ai/auth/oauth/github', params: { attribution: blob }
      end

      it 'stamps the channel on a user CREATED through OAuth' do
        new_user = User.new(email: 'fresh@example.com', password: 'x' * 20, terms_accepted: true)
        new_user.save!
        allow(Levelcode::ProviderOAuth).to receive(:github_user).and_return(new_user)

        start_oauth_with_attribution
        get '/ai/auth/callback', params: { code: 'gh', state: 'teststate' }

        stored = new_user.reload.signup_attribution
        expect(stored['source']).to eq('linkedin')
        expect(stored.dig('params', 'linkedin')).to eq('anastasia')
        expect(stored['recorded_at']).to be_present
      end

      # Acquisition attribution, not last-touch: someone who signed up long ago and
      # today arrives through a referral link was not acquired by that channel, and
      # crediting them would inflate the partner's conversions.
      it 'does NOT stamp an existing user who merely signs in through a referral link' do
        existing = User.create!(email: 'old@example.com', password: 'x' * 20, terms_accepted: true)
        existing.reload # clears previously_new_record?
        allow(Levelcode::ProviderOAuth).to receive(:github_user).and_return(existing)

        start_oauth_with_attribution
        get '/ai/auth/callback', params: { code: 'gh', state: 'teststate' }

        expect(existing.reload.signup_attribution).to be_nil
      end

      it 'ignores an unparseable attribution blob instead of failing the sign-in' do
        new_user = User.new(email: 'junk@example.com', password: 'x' * 20, terms_accepted: true)
        new_user.save!
        allow(Levelcode::ProviderOAuth).to receive(:github_user).and_return(new_user)

        start_oauth_with_attribution('not json{{{')
        get '/ai/auth/callback', params: { code: 'gh', state: 'teststate' }

        expect(response).to redirect_to('/ai/account')
        expect(new_user.reload.signup_attribution).to be_nil
      end

      # The session is a ~4 KB cookie. A character-based clamp lets multi-byte UTF-8
      # through at up to 4x the intended size, and an overflowing cookie takes the
      # OAuth `state` with it — turning a sign-in into ?error=session_expired.
      it 'survives an oversized multi-byte attribution blob without breaking sign-in' do
        new_user = User.new(email: 'big@example.com', password: 'x' * 20, terms_accepted: true)
        new_user.save!
        allow(Levelcode::ProviderOAuth).to receive(:github_user).and_return(new_user)

        huge = { source: 'linkedin', params: { linkedin: 'ф' * 3_000 } }.to_json
        start_oauth_with_attribution(huge)
        get '/ai/auth/callback', params: { code: 'gh', state: 'teststate' }

        # The sign-in still completes; the truncated blob is simply unparseable and
        # treated as organic rather than corrupting the session.
        expect(response).to redirect_to('/ai/account')
      end

      it 'drops params outside the whitelist' do
        new_user = User.new(email: 'evil@example.com', password: 'x' * 20, terms_accepted: true)
        new_user.save!
        allow(Levelcode::ProviderOAuth).to receive(:github_user).and_return(new_user)

        start_oauth_with_attribution(
          { source: 'linkedin', params: { linkedin: 'anastasia', evil: 'x' } }.to_json
        )
        get '/ai/auth/callback', params: { code: 'gh', state: 'teststate' }

        expect(new_user.reload.signup_attribution['params'].keys).to eq([ 'linkedin' ])
      end
    end
  end

  describe 'POST /ai/signout' do
    it 'clears the session and returns JSON' do
      post '/ai/signout'
      expect(response).to have_http_status(:ok)
      expect(json).to eq('ok' => true)
    end
  end

  describe 'GET /ai/auth/handoff (editor -> browser SSO)' do
    let(:user) { User.create!(email: 'handoff@example.com', password: 'password123', terms_accepted: true) }

    it 'redeems a valid code, signs the browser in, and redirects to /ai/account' do
      allow(Levelcode::OneTimeCode).to receive(:redeem).with('good-code').and_return(user)

      get '/ai/auth/handoff', params: { code: 'good-code' }
      expect(response).to redirect_to('/ai/account')

      # Session established — the account API now authenticates via the cookie (no re-login).
      get '/api/levelcode/v1/account/profile'
      expect(response).to have_http_status(:ok)
      expect(json['email']).to eq('handoff@example.com')
    end

    it 'redirects to /ai/login on an invalid or expired code' do
      allow(Levelcode::OneTimeCode).to receive(:redeem).and_raise(Levelcode::OneTimeCode::InvalidCode, 'expired')

      get '/ai/auth/handoff', params: { code: 'nope' }
      expect(response).to redirect_to('/ai/login?error=link_expired')
    end
  end

  describe 'POST /ai/authorize_editor (browser -> PKCE-bound editor code)' do
    let(:user) { User.create!(email: 'launch@example.com', password: 'password123', terms_accepted: true) }

    def sign_in_browser(code)
      allow(Levelcode::OneTimeCode).to receive(:redeem).with(code).and_return(user)
      get '/ai/auth/handoff', params: { code: code }
      expect(response).to redirect_to('/ai/account')
    end

    it 'mints a PKCE-BOUND editor code for the signed-in browser session (no second login)' do
      sign_in_browser('sess-a')
      allow(Levelcode::OneTimeCode).to receive(:issue).with(user, 'chal').and_return('bound-code')

      post '/ai/authorize_editor', params: { redirect_uri: editor_uri, code_challenge: 'chal' }

      expect(response).to have_http_status(:ok)
      loc = URI.parse(json['redirect'])
      expect(loc.scheme).to eq('levelcode')
      expect(Rack::Utils.parse_query(loc.query)['code']).to eq('bound-code')
    end

    it 'FAILS CLOSED without a code_challenge (an unbound code would be interceptable)' do
      sign_in_browser('sess-b')

      post '/ai/authorize_editor', params: { redirect_uri: editor_uri } # no challenge

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig('error', 'code')).to eq('invalid_request')
    end

    it 'rejects a non-editor redirect_uri (no open redirect)' do
      sign_in_browser('sess-c')

      post '/ai/authorize_editor', params: { redirect_uri: 'https://evil.example/steal', code_challenge: 'chal' }

      expect(response).to have_http_status(:unprocessable_content)
    end

    # WHICH addresses are the editor's. The scheme is the editor build's identity; the host is the
    # extension id and the path its auth route. One example per address, so that the list cannot
    # grow or shrink without one of these changing.
    {
      'levelcode://levelcode.levelcode-ai/auth/callback' => 'the shipped editor',
      'atom-plus-plus://levelcode.levelcode-ai/auth/callback' => 'a build from before the rename'
    }.each_with_index do |(address, whose), i|
      it "hands the code to #{whose} — #{address}" do
        sign_in_browser("sess-takes-#{i}")
        allow(Levelcode::OneTimeCode).to receive(:issue).with(user, 'chal').and_return('bound-code')

        post '/ai/authorize_editor', params: { redirect_uri: "#{address}?windowId=2", code_challenge: 'chal' }

        expect(response).to have_http_status(:ok)
        expect(json['redirect']).to eq("#{address}?windowId=2&code=bound-code")
      end
    end

    {
      'levelcode-dev://levelcode.levelcode-ai/auth/callback' => 'a scheme that is not on the list',
      'levelcode://evil.example/auth/callback' => 'the right scheme on another host',
      'levelcode://levelcode.levelcode-ai/elsewhere' => 'the right host on another path',
      'https://levelcode.levelcode-ai/auth/callback' => 'the right host and path over https',
      'levelcode:levelcode.levelcode-ai/auth/callback' => 'an address with no host at all'
    }.each_with_index do |(address, what), i|
      it "mints nothing for #{what} — #{address}" do
        sign_in_browser("sess-refuses-#{i}")
        expect(Levelcode::OneTimeCode).not_to receive(:issue)

        post '/ai/authorize_editor', params: { redirect_uri: address, code_challenge: 'chal' }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig('error', 'code')).to eq('invalid_request')
      end
    end

    context 'on a server told to take a development editor (LEVELCODE_EXTRA_EDITOR_SCHEMES)' do
      before { with_extra_editor_schemes('levelcode-dev') }

      it 'hands the code to the development editor' do
        sign_in_browser('sess-dev-a')
        allow(Levelcode::OneTimeCode).to receive(:issue).with(user, 'chal').and_return('bound-code')

        post '/ai/authorize_editor',
             params: { redirect_uri: 'levelcode-dev://levelcode.levelcode-ai/auth/callback?windowId=2', code_challenge: 'chal' }

        expect(response).to have_http_status(:ok)
        expect(json['redirect']).to eq('levelcode-dev://levelcode.levelcode-ai/auth/callback?windowId=2&code=bound-code')
      end

      it 'goes on handing it to the shipped editor — the list grew, it was not replaced' do
        sign_in_browser('sess-dev-b')
        allow(Levelcode::OneTimeCode).to receive(:issue).with(user, 'chal').and_return('bound-code')

        post '/ai/authorize_editor', params: { redirect_uri: editor_uri, code_challenge: 'chal' }

        expect(response).to have_http_status(:ok)
        expect(json['redirect']).to eq("#{editor_uri}?code=bound-code")
      end

      it 'mints nothing for the development scheme on another host' do
        sign_in_browser('sess-dev-c')
        expect(Levelcode::OneTimeCode).not_to receive(:issue)

        post '/ai/authorize_editor', params: { redirect_uri: 'levelcode-dev://evil.example/auth/callback', code_challenge: 'chal' }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    # A list that could be talked into a web scheme would post the code to a web host; the setting
    # cannot add one, whatever it says.
    it 'mints nothing for https even on a server whose setting names it' do
      with_extra_editor_schemes('https, levelcode-dev')
      sign_in_browser('sess-https')
      expect(Levelcode::OneTimeCode).not_to receive(:issue)

      post '/ai/authorize_editor', params: { redirect_uri: 'https://levelcode.levelcode-ai/auth/callback', code_challenge: 'chal' }

      expect(response).to have_http_status(:unprocessable_content)
    end

    context 'on a server told of a web editor (LEVELCODE_WEB_EDITOR_ORIGINS)' do
      let(:web_callback) do
        'https://editor.levelcode.test/callback.html?vscode-reqid=1&vscode-scheme=levelcode' \
          '&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback'
      end

      before { with_web_editor('https://editor.levelcode.test') }

      it 'hands a PKCE-bound code to the page for the signed-in browser — no second login' do
        sign_in_browser('sess-web-a')
        allow(Levelcode::OneTimeCode).to receive(:issue).with(user, 'chal').and_return('bound-code')

        post '/ai/authorize_editor', params: { redirect_uri: web_callback, code_challenge: 'chal' }

        expect(response).to have_http_status(:ok)
        expect(json['redirect']).to eq("#{web_callback}&code=bound-code")
      end

      it 'fails closed without a code_challenge' do
        sign_in_browser('sess-web-b')
        expect(Levelcode::OneTimeCode).not_to receive(:issue)

        post '/ai/authorize_editor', params: { redirect_uri: web_callback }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig('error', 'code')).to eq('invalid_request')
      end

      {
        'an origin that is not on the list' => 'https://evil.test/callback.html?vscode-reqid=1&vscode-scheme=levelcode&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback',
        'the account site itself' => 'https://levelcode.ai/callback.html?vscode-reqid=1&vscode-scheme=levelcode&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback',
        'the listed origin over http' => 'http://editor.levelcode.test/callback.html?vscode-reqid=1&vscode-scheme=levelcode&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback',
        'the listed origin, another page' => 'https://editor.levelcode.test/?vscode-reqid=1&vscode-scheme=levelcode&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback',
        'the page with no vscode-* parameters' => 'https://editor.levelcode.test/callback.html'
      }.each_with_index do |(what, address), i|
        it "mints nothing for #{what}" do
          sign_in_browser("sess-web-refuses-#{i}")
          expect(Levelcode::OneTimeCode).not_to receive(:issue)

          post '/ai/authorize_editor', params: { redirect_uri: address, code_challenge: 'chal' }

          expect(response).to have_http_status(:unprocessable_content)
          expect(json.dig('error', 'code')).to eq('invalid_request')
        end
      end

      it 'goes on handing the code to the desktop editor' do
        sign_in_browser('sess-web-c')
        allow(Levelcode::OneTimeCode).to receive(:issue).with(user, 'chal').and_return('bound-code')

        post '/ai/authorize_editor', params: { redirect_uri: "#{editor_uri}?windowId=2", code_challenge: 'chal' }

        expect(json['redirect']).to eq("#{editor_uri}?windowId=2&code=bound-code")
      end
    end

    context 'on a server told of the web editor\'s extension host (LEVELCODE_WEB_EXTENSION_HOST_ORIGINS)' do
      before do
        with_web_editor('https://editor.levelcode.test',
                        extension_hosts: 'https://*.ext.levelcode.test, https://ext.levelcode.test, http://*.localhost:8801')
      end

      {
        'a session of the extension host' => 'https://v--abc123.ext.levelcode.test',
        'the extension host\'s domain, named exactly' => 'https://ext.levelcode.test',
        'a local development session of it' => 'http://v--abc.localhost:8801'
      }.each_with_index do |(what, base), i|
        it "mints nothing for the callback page on #{what}" do
          sign_in_browser("sess-host-#{i}")
          expect(Levelcode::OneTimeCode).not_to receive(:issue)

          post '/ai/authorize_editor',
               params: { code_challenge: 'chal',
                         redirect_uri: "#{base}/callback.html?vscode-reqid=1&vscode-scheme=levelcode" \
                                       '&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback' }

          expect(response).to have_http_status(:unprocessable_content)
          expect(json.dig('error', 'code')).to eq('invalid_request')
        end
      end
    end

    # Production, until the web editor ships.
    it 'mints nothing for the web editor\'s page on a server that has not been told of one' do
      sign_in_browser('sess-web-off')
      expect(Levelcode::OneTimeCode).not_to receive(:issue)

      post '/ai/authorize_editor',
           params: { code_challenge: 'chal',
                     redirect_uri: 'https://editor.levelcode.test/callback.html?vscode-reqid=1&vscode-scheme=levelcode' \
                                   '&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig('error', 'code')).to eq('invalid_request')
    end

    it 'does not mint for an anonymous request' do
      post '/ai/authorize_editor', params: { redirect_uri: editor_uri, code_challenge: 'chal' }, as: :json
      expect(response).not_to have_http_status(:ok)
    end
  end

  describe 'POST /ai/checkout' do
    let(:user) { User.create!(email: 'buyer@example.com', password: 'password123', terms_accepted: true) }

    # Sign the browser in (Devise session cookie) so authenticate_user!/current_user resolve.
    before do
      allow(Levelcode::OneTimeCode).to receive(:redeem).with('handoff').and_return(user)
      get '/ai/auth/handoff', params: { code: 'handoff' }
      expect(response).to redirect_to('/ai/account')
    end

    def price_double(id:, amount:, lookup_key: 'orbits_pro')
      double('Stripe::Price', id: id, unit_amount: amount, lookup_key: lookup_key)
    end

    def stub_price(price)
      allow(Stripe::Price).to receive(:list).and_return(double('price_list', data: [ price ]))
    end

    # Existing Stripe subscription whose single item sits at `amount` (in cents via unit_amount), with the
    # period the customer has already paid for running until 20 days out.
    def stub_current_stripe_sub(amount:, price_id: 'price_current', lookup_key: 'orbits_ultra')
      item = double('item', id: 'si_1',
                            price: double('cur_price', id: price_id, unit_amount: amount, lookup_key: lookup_key),
                            current_period_start: 1.day.ago.to_i, current_period_end: 20.days.from_now.to_i)
      allow(Stripe::Subscription).to receive(:retrieve).with('sub_x')
                                                       .and_return(double('sub', id: 'sub_x', schedule: nil,
                                                                                 items: double('items', data: [ item ])))
    end

    # A subscription schedule mirroring the current (paid-through) phase.
    def stub_schedule
      phase = double('phase', start_date: 1.day.ago.to_i, end_date: 20.days.from_now.to_i)
      sched = double('sched', id: 'sub_sched_1', phases: [ phase ])
      allow(Stripe::SubscriptionSchedule).to receive(:create).and_return(sched)
      allow(Stripe::SubscriptionSchedule).to receive(:update).and_return(sched)
      sched
    end

    context 'first purchase (no active levelcode subscription)' do
      it 'opens a Checkout Session and returns { url } (never an in-place update)' do
        stub_price(price_double(id: 'price_pro', amount: 2000))
        expect(Stripe::Subscription).not_to receive(:update)
        expect(Stripe::Checkout::Session).to receive(:create)
          .with(hash_including(customer: 'cus_test', mode: 'subscription'))
          .and_return(double('session', url: 'https://checkout.stripe.com/s/1'))

        post '/ai/checkout', params: { lookup_key: 'orbits_pro' }

        expect(response).to have_http_status(:ok)
        expect(json).to eq('url' => 'https://checkout.stripe.com/s/1')
      end
    end

    context 'with an active levelcode subscription' do
      before { user.subscriptions.create!(product: 'levelcode', subscription_id: 'sub_x', status: 'active') }

      it 'upgrade → prorates on the SAME subscription (no second full-price checkout)' do
        stub_price(price_double(id: 'price_pro_plus', amount: 4000))
        stub_current_stripe_sub(amount: 2000) # currently on Pro
        expect(Stripe::Checkout::Session).not_to receive(:create)
        expect(Stripe::Subscription).to receive(:update).with(
          'sub_x',
          hash_including(proration_behavior: 'create_prorations',
                         items: [ hash_including(id: 'si_1', price: 'price_pro_plus') ])
        )

        post '/ai/checkout', params: { lookup_key: 'orbits_pro_plus' }

        expect(response).to have_http_status(:ok)
        expect(json).to include('status' => 'plan_changed', 'change_type' => 'upgraded')
        expect(json).not_to have_key('url')
      end

      # Ultra → Pro must NOT touch the subscription item now: that would drop the wallet to Pro mid-period
      # via customer.subscription.updated, losing the tier the customer already paid for. It is scheduled at
      # the period boundary instead.
      it 'downgrade → schedules the switch at period end, never swaps the item now' do
        stub_price(price_double(id: 'price_pro', amount: 2000, lookup_key: 'orbits_pro'))
        stub_current_stripe_sub(amount: 10_000, lookup_key: 'orbits_ultra') # currently on Ultra
        stub_schedule
        expect(Stripe::Checkout::Session).not_to receive(:create)
        expect(Stripe::Subscription).not_to receive(:update)
        expect(Stripe::SubscriptionSchedule).to receive(:update).with(
          'sub_sched_1',
          hash_including(end_behavior: 'release',
                         phases: [ hash_including(items: [ { price: 'price_current', quantity: 1 } ]),
                                   hash_including(items: [ { price: 'price_pro', quantity: 1 } ]) ])
        ).and_return(double('sched', id: 'sub_sched_1'))

        post '/ai/checkout', params: { lookup_key: 'orbits_pro' }

        expect(response).to have_http_status(:ok)
        expect(json['change_type']).to eq('downgraded')
        expect(json['message']).to include('keep your current plan')
      end

      it 'same plan → 422 already_subscribed, no Stripe write' do
        stub_price(price_double(id: 'price_same', amount: 4000))
        stub_current_stripe_sub(amount: 4000, price_id: 'price_same')
        expect(Stripe::Checkout::Session).not_to receive(:create)
        expect(Stripe::Subscription).not_to receive(:update)

        post '/ai/checkout', params: { lookup_key: 'orbits_pro_plus' }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig('error', 'code')).to eq('already_subscribed')
      end
    end
  end
end
