Rails.application.routes.draw do
  root "graph#show"
  get "graph/data", to: "graph#data", as: :graph_data

  resources :people do
    resources :interactions, only: %i[create destroy]
    member { post :draft }
    collection do
      post :intake
      patch :rate
    end
  end
  resources :imports, only: %i[new create show update]
  resources :companies, only: %i[index create update]
  resources :feed_items, only: :update
  resource :profile, only: %i[show update] do
    post :analyze
    post :resume
    post :fill
    post :api_key
  end
  resource :refresh, only: %i[create show]

  get "up" => "rails/health#show", as: :rails_health_check
end
