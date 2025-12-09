Rails.application.routes.draw do
  devise_for :users, controllers: {
    sessions: 'users/sessions'
  }
  
  authenticate :user do
    resources :short_urls, only: [:index, :new, :create, :destroy] do
      collection do
        get :suggest_keys
        post :check_availability
      end
    end
  end
  
  get '/:short_uri', to: 'short_urls#redirect', as: :short_redirect
  
  root 'home#index'
end