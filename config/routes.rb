Rails.application.routes.draw do
  root "kainga#index"

  controller :kainga do
    get "kainga/index", action: :index
    get "kainga/mobile", action: :mobile
    get "mobile", action: :mobile
  end

  controller :mobile_forecast do
    get "mobile_forecast/index", action: :index
    post "mobile_forecast/geo_location", action: :geo_location
    get "mobile_forecast/full", action: :full
    get "mobile_forecast", action: :index
  end

  controller :forecast do
    scope path: "forecast" do
      get "view", action: :index, as: :forecast_view
      get "full", action: :full, as: :forecast_full
      get "text_only", action: :text_only, as: :forecast_text_only
      post "summary", action: :summary, as: :forecast_summary
      post "geo_location", action: :geo_location, as: :forecast_geo_location
      get "dual", action: :dual, as: :forecast_dual
      post "dual_full", action: :dual_full, as: :forecast_dual_full
      post "dual_geo_location", action: :dual_geo_location, as: :forecast_dual_geo_location
    end
  end
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
