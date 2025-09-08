Rails.application.routes.draw do
  get "canyon_times/show"
  get "translator/index"
  get "dabs/index"
  root "kainga#index"

  controller :kainga do
    get "kainga/index", action: :index
    get "kainga/mobile", action: :mobile
    get "mobile", action: :mobile
    get "privacy", action: :privacy
  end

  controller :mobile_forecast do
    get "mobile_forecast/index", action: :index
    post "mobile_forecast/geo_location", action: :geo_location
    get "mobile_forecast/weather_map", action: :weather_map
    get "mobile_forecast/full", action: :full
    get "mobile_forecast", action: :index
  end

  controller :translator do
    get "translator", action: :index
    get "translator/index", action: :index
    get "translator/create", action: :create
    get "translator/show", action: :show
    get "translator/switch_layout", action: :switch_layout
  end

  controller :forecast do
    get "forecast", action: :index, as: :forecast
    scope path: "forecast" do
      get "view", action: :index, as: :forecast_view
      get "full", action: :full, as: :forecast_full
      get "text_only", action: :text_only, as: :forecast_text_only
      post "summary", action: :summary, as: :forecast_summary
      post "geo_location", action: :geo_location, as: :forecast_geo_location
      get "dual", action: :dual, as: :forecast_dual
      post "dual_full", action: :dual_full, as: :forecast_dual_full
      post "dual_geo_location", action: :dual_geo_location, as: :forecast_dual_geo_location
      get "radar_for_locale", action: :radar_for_locale, as: :radar_for_locale
      get "radar_for_locale_web", action: :radar_for_locale_web, as: :radar_for_locale_web
    end
  end

  namespace :admin do
    root to: "resorts#index"
    resources :resorts do
      resources :resort_filters, only: [ :new, :create ]
      resources :cameras
    end
    resources :resort_filters, only: [ :edit, :update, :destroy, :create, :show ]
    get "parking_profiles/:resort_id/:season/edit", to: "parking_profiles#edit", as: :edit_parking_profile
    get "parking_profiles/:resort_id/:season/create", to: "parking_profiles#create", as: :create_parking_profile
    patch "parking_profiles/:resort_id/:season", to: "parking_profiles#update", as: :update_parking_profile
    get "parking_profiles/:resort_id/:season", to: "parking_profiles#show", as: :show_parking_profile
  end

  # API endpoints
  namespace :api do
    namespace :v1 do
      get "weather/index"
      get "weather/forecasts"
      get "weather/hourly"
      get "weather/radar"
      get "weather/period"
      get "weather/alerts"
      get "canyon_times/times"
      get "canyon_times/travel_times"
      get "canyon_times/resorts"
      get "canyon_times/cameras"
      get "canyon_times/featured_cameras"
      get "canyon_times/parking_cameras"
      get "canyon_times/parking_profile"
      get "canyon_times/alerts_events"
      get "canyon_times/directions"
      get "canyon_times/signs"
      get "weather/discussion"
      get "weather/watches_fire_alerts"
    end
  end

  resources :dabs, only: [ :index ]

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
