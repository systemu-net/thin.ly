require "sidekiq/web"
require "sidekiq/cron/web"

Rails.application.routes.draw do
  devise_for :users, defaults: { format: :json }, path: "users", controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations"
  }
  devise_scope :user do
    post "users/auth/google", to: "users/google_auth#create", defaults: { format: :json }
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  mount Sidekiq::Web => "/sidekiq" if Rails.env.development?

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # Defines the root path route ("/")
  # root "posts#index"

  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      resources :links, only: %i[index show create update destroy], param: :lookup_code do
        collection do
          get :search

          scope :governance, as: :governance, controller: "link_governance" do
            post :pause_all
          end
        end
        member do
          get :analytics

          # Governance sub-endpoints on each link
          scope :governance, as: :governance, controller: "link_governance" do
            patch :transition
            patch :destination
            get :audit_log
            get :destination_history
          end
        end
        resources :routing_rules, only: %i[index show create update destroy]
      end

      resources :campaigns, only: %i[index show create update destroy] do
        member do
          post :pause
          post :resume
        end
      end

      resources :qr_codes, only: %i[index create show destroy]

      # User profile and avatar management
      resource :user, only: %i[show update] do
        # Avatar routes without format constraints to allow multipart/form-data
        patch :avatar, action: :update_avatar, defaults: { format: nil }
        delete :avatar, action: :destroy_avatar, defaults: { format: nil }
      end

      # Owner's public @handle profile (link-in-bio). Singular resource — the
      # current user has exactly one profile.
      resource :profile, only: %i[show update], controller: "profiles" do
        post :publish
      end
      get "handles/check", to: "profiles#check_handle"

      # Owner curation of which governed links appear on the profile.
      get   "profile/links", to: "profile_links#index"
      patch "profile/links", to: "profile_links#update"

      # Public, by-handle profile (no auth; privacy-enforced). Handles may
      # contain dots, so the greedy constraint keeps "sergii.demianchuk" intact.
      get "profiles/:handle/qr", to: "public_profiles#qr", constraints: { handle: /[a-z0-9_.\-]+/i }
      get "profiles/:handle", to: "public_profiles#show", constraints: { handle: /[a-z0-9_.\-]+/i }

      resources :subscriptions, only: %i[index create destroy]

      resources :brand_pages, param: :lookup_code do
        collection do
          post :generate
          post :preview
          get :analytics
        end

        member do
          post :publish
          post :unpublish
        end

        # Nested resources for managing resources (links, qr_codes, etc) on brand pages
        scope module: :brand_pages do
          resources :resources, param: :id do
            collection do
              patch :reorder
            end
          end
        end
      end

      resources :webhooks, only: %i[create]

      resources :billings, only: %i[create]

      resources "checkouts", only: %i[create]
      get "checkouts/success", to: "checkouts#success"
      get "checkouts/cancel", to: "checkouts#cancel"

      get "/current_user", to: "current_user#index"

      # Presigned direct-to-S3 image uploads
      post "/uploads/presign", to: "uploads#presign"

      # Aggregate analytics across the current user's links
      get "/analytics/clicks_timeline", to: "analytics#clicks_timeline"

      # Track page views
      match "/track/view", to: "track#cors_preflight", via: [ :options ]
      post "/track/view", to: "track#view"

      # Page views analytics
      resources :page_views, only: [ :index ] do
        collection do
          get :by_brand_page
        end
      end
    end

    # ---- LevelCode Cloud (Levelcode) — isolated namespace (SPEC §3). Sibling of :v1. ----
    # Paths: /api/levelcode/v1/*  ·  controllers Api::Levelcode::V1::*
    namespace :levelcode do
      namespace :v1 do
        # Auth (SPEC §2, §3)
        post  "auth/callback",        to: "auth#callback"       # levelcode.ai server -> mint (service-token)
        post  "auth/email/request",   to: "auth#email_request"  # passwordless OTP: send code
        post  "auth/email/verify",    to: "auth#email_verify"   # passwordless OTP: verify code -> mint
        match "auth/login",           to: "auth#login", via: %i[get post]
        post  "auth/signup",          to: "auth#signup"
        post  "auth/exchange",        to: "auth#exchange"   # PKCE one-time code -> tokens
        post  "auth/refresh",         to: "auth#refresh"
        post  "auth/signout",         to: "auth#signout"
        post  "auth/web_handoff",     to: "auth#web_handoff"    # editor token -> one-time browser sign-in URL

        # Billing + account (SPEC §3, §6)
        get   "pricing",         to: "pricing#index"
        resources :checkouts,    only: %i[create]
        resources :billings,     only: %i[create]
        get   "account/profile",  to: "account#profile"
        get   "account/usage",    to: "account#usage"
        get   "account/activity", to: "account#activity"   # GitHub-style contribution heatmap data
        get   "account/models",   to: "account#models"     # plan model roster + credits + turns-left
        post  "feedback",         to: "feedback#create"    # editor thumbs up/down -> per-model signal

        # Admin dashboard (role: admin only)
        get   "admin/summary",    to: "admin#summary"
        get   "admin/users",      to: "admin#users"

        # AI gateway (SPEC §4). The editor routes gateway traffic through its
        # OpenAI-compatible adapter, which POSTs to `<base>/chat/completions`
        # (base = …/api/levelcode/v1/ai). Expose that path so the request lands on
        # this bearer-authed API controller instead of falling through to the
        # HTML catch-all. `ai/chat` kept as an alias for the SPEC/tests.
        post  "ai/chat/completions", to: "ai#chat"
        post  "ai/chat",             to: "ai#chat"
      end
    end
  end

  # namespace :stripe do
  #   post "webhooks", to: "stripe/webhooks#create"
  # end

  # ---- LevelCode Cloud account app (onetime SPA, served at /ai/* by static#ui) ----
  # Only the server-side flows the SPA delegates to live here: OAuth redirect +
  # callback (server-side code exchange), and the session-establishing / Stripe
  # writes (CSRF-protected via Levelcode::WebController). MUST be declared BEFORE the
  # "*ui" catch-all so they resolve to the controller; GET /ai, /ai/login,
  # /ai/pricing, /ai/account fall through to static#ui (the levelcode shell).
  scope "ai", module: "levelcode", as: "ai" do
    get   "auth/oauth/:provider", to: "web#oauth_start",    as: :auth_oauth
    get   "auth/callback",        to: "web#oauth_callback", as: :auth_callback
    get   "auth/handoff",         to: "web#handoff",        as: :auth_handoff  # editor->browser SSO: redeem code -> session

    post  "auth/email",           to: "web#email_request",  as: :auth_email
    post  "auth/verify",          to: "web#email_verify",   as: :auth_verify
    post  "authorize_editor",     to: "web#authorize_editor", as: :authorize_editor  # browser session -> PKCE-bound editor code
    post  "checkout",             to: "web#checkout",        as: :checkout
    post  "billing",              to: "web#billing",         as: :billing
    match "signout",              to: "web#signout",         as: :signout, via: %i[delete post]
    get   "csrf",                 to: "web#csrf",            as: :csrf
  end

  get "/unsafe-link", to: "static#unsafe_link", as: :unsafe_link
  get "/link-not-found", to: "static#link_not_found", as: :link_not_found
  # The link-shortener lookup only applies on thin.ly hosts. levelcode.ai is the
  # account app (not a shortener), so a 7-char bare path there (e.g. /pricing)
  # must fall through to static#ui — which redirects it into the /ai app — instead
  # of resolving as a short code.
  constraints(->(req) { !StaticController::LEVELCODE_HOSTS.include?(req.host) }) do
    get "/:lookup_code" => "api/v1/links#lookup_code", as: :lookup_code, constraints: { lookup_code: /[a-zA-Z0-9]{7}/ }
  end
  match "*ui", to: "static#ui", via: :get, constraints: ->(request) { request.format.html? && !request.path.start_with?("/api/") }
  match "*path", to: "static#not_found", via: :all

  root "static#ui"
end
