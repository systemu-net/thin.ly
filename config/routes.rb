require "sidekiq/web"

Rails.application.routes.draw do
  devise_for :users, defaults: { format: :json }, path: "users", controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations"
  }
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
        end
      end

      resources :qr_codes, only: %i[index create show destroy]

      resources :subscriptions, only: %i[index create destroy]

      resources :brand_pages, param: :lookup_code do
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
  end

  # namespace :stripe do
  #   post "webhooks", to: "stripe/webhooks#create"
  # end

  get "/unsafe-link", to: "static#unsafe_link", as: :unsafe_link
  get "/:lookup_code" => "api/v1/links#lookup_code", as: :lookup_code, constraints: { lookup_code: /[a-zA-Z0-9]{7}/ }
  match "*ui", to: "static#ui", via: :get, constraints: ->(request) { request.format.html? && !request.path.start_with?("/api/") }
  match "*path", to: "static#not_found", via: :all

  root "static#ui"
end
