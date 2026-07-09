Rails.application.routes.draw do
  # Add your docs to an agent over MCP (needs `gem "mcp"`):
  # post "/mcp" => "docs_kit/mcp#create"
  # match "/mcp" => "docs_kit/mcp#method_not_allowed", via: %i[get delete]
  get "/llms-full.txt" => "docs_kit/llms#full", as: :llms_full
  get "/llms.txt" => "docs_kit/llms#index", as: :llms
  root "landings#show"
  get "/docs/search" => "docs_kit/search#index", as: :docs_search
  get "docs/:doc(.:format)" => "docs#show", as: :doc
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
