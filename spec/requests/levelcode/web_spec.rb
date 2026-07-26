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
