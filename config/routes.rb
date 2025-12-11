Rails.application.routes.draw do
  # ActiveAdmin routes - yeh sabse pehle hone chahiye
  ActiveAdmin.routes(self)

  devise_for :admin_users, ActiveAdmin::Devise.config

  devise_for :users, controllers: {
    sessions: "users/sessions"
  }

  # Authenticated users ke liye root ko dashboard set karo
  authenticated :user do
    root "short_urls#dashboard", as: :authenticated_root

    # Dashboard route explicitly bhi define karo
    get "dashboard", to: "short_urls#dashboard", as: :dashboard

    # Short URLs listing
    get "short_urls", to: "short_urls#index", as: :short_urls

    # Stats route with full path
    resources :short_urls, only: [] do
      member do
        get :stats  # This will create /short_urls/:id/stats
      end
    end

    # Other short_url actions with empty path
    resources :short_urls, only: [ :create, :destroy ], path: "" do
      collection do
        get :suggest_keys
        post :check_availability
      end
    end
  end

  # Non-authenticated users ke liye landing page
  root "home#index"

  # Tracking endpoint - redirect se pehle hona chahiye
  post "/:short_uri/track", to: "short_urls#track_click",
       constraints: { short_uri: /(?!admin|short_urls|dashboard)[^\/]+/ }

  # Short URL redirect - yeh sabse last mein hona chahiye
  get "/:short_uri", to: "short_urls#redirect", as: :short_redirect,
      constraints: { short_uri: /(?!admin|short_urls|dashboard)[^\/]+/ }
end
