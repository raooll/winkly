# config/routes.rb

Rails.application.routes.draw do
  devise_for :users, controllers: {
    sessions: "users/sessions"
  }

  # Authenticated users ke liye root ko short_urls#index set karo
  authenticated :user do
    root "short_urls#index", as: :authenticated_root

    resources :short_urls, only: [ :create, :destroy ], path: "" do
      collection do
        get :suggest_keys
        post :check_availability
      end
    end
  end

  # Non-authenticated users ke liye landing page
  root "home#index"

  # Short URL redirect - yeh sabse last mein hona chahiye
  get "/:short_uri", to: "short_urls#redirect", as: :short_redirect, constraints: { short_uri: /[^\/]+/ }
end
