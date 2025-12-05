Rails.application.routes.draw do
  # --------------------------------------------------------
  # DOMAIN ROUTING (HOST-BASED)
  # --------------------------------------------------------

  # === Canyon Traveller frontend (www.canyontraveller.com) ===
  constraints(host: "www.canyontraveller.com") do
    root "canyon_traveller#index", as: :canyon_traveller_root

    controller :canyon_traveller do
      get "/",         action: :index
      get "index",     action: :index
      get "mobile",    action: :mobile
      get "traffic",   action: :traffic
      get "cameras",   action: :cameras
    end
  end

  # === Canyon Traveller frontend (www.canyontravellers.com) ===
  constraints(host: "www.canyontravellers.com") do
    root "canyon_traveller#index", as: :canyon_travellers_root

    controller :canyon_traveller do
      get "/",         action: :index
      get "index",     action: :index
      get "mobile",    action: :mobile
      get "traffic",   action: :traffic
      get "cameras",   action: :cameras
    end
  end

  # === Aura Weather frontend (www.auraweatherforecasts.com) ===
  constraints(host: "www.auraweatherforecasts.com") do
    root "kainga#index", as: :aura_weather_forecasts_root

    controller :kainga do
      get "kainga/index",  action: :index
      get "kainga/mobile", action: :mobile
      get "mobile",        action: :mobile
      get "privacy",       action: :privacy
    end

    controller :mobile_forecast do
      get "mobile_forecast",                action: :index
      get "mobile_forecast/index",          action: :index
      post "mobile_forecast/geo_location",  action: :geo_location
      get "mobile_forecast/weather_map",    action: :weather_map
      get "mobile_forecast/full",           action: :full
    end
  end

  # --------------------------------------------------------
  # DEFAULT ROOT (non-domain or local dev)
  # --------------------------------------------------------
  root "kainga#index", as: :kainga_root

  # --------------------------------------------------------
  # PUBLIC SITE ROUTES (shared or fallback)
  # --------------------------------------------------------
  controller :kainga do
    get "privacy", action: :privacy
  end

  controller :translator do
    get "translator",            action: :index
    get "translator/index",      action: :index
    get "translator/create",     action: :create
    get "translator/show",       action: :show
    get "translator/switch_layout", action: :switch_layout
  end

  controller :canyon_traveller do
    get "canyon_traveller",            action: :index
    get "canyon_traveller/index",      action: :index
  end

  # Forecast web UI
  controller :forecast do
    get "forecast",                       action: :index, as: :forecast
    scope path: "forecast" do
      get "view",                         action: :index,              as: :forecast_view
      get "full",                         action: :full,               as: :forecast_full
      get "text_only",                    action: :text_only,          as: :forecast_text_only
      post "summary",                     action: :summary,            as: :forecast_summary
      post "geo_location",                action: :geo_location,       as: :forecast_geo_location
      get "dual",                         action: :dual,               as: :forecast_dual
      post "dual_full",                   action: :dual_full,          as: :forecast_dual_full
      post "dual_geo_location",           action: :dual_geo_location,  as: :forecast_dual_geo_location
      get "radar_for_locale",             action: :radar_for_locale,   as: :radar_for_locale
      get "radar_for_locale_web",         action: :radar_for_locale_web, as: :radar_for_locale_web
    end
  end

  # --------------------------------------------------------
  # ADMIN PANEL
  # --------------------------------------------------------
  namespace :admin do
    root to: "resorts#index"

    resources :resorts do
      resources :resort_filters, only: [ :new, :create ]
      resources :cameras
    end

    resources :resort_filters, only: [ :edit, :update, :destroy, :create, :show ]

    get  "parking_profiles/:resort_id/:season/edit",    to: "parking_profiles#edit",   as: :edit_parking_profile
    get  "parking_profiles/:resort_id/:season/create",  to: "parking_profiles#create", as: :create_parking_profile
    patch "parking_profiles/:resort_id/:season",        to: "parking_profiles#update", as: :update_parking_profile
    get "parking_profiles/:resort_id/:season",         to: "parking_profiles#show",   as: :show_parking_profile
  end

  # --------------------------------------------------------
  # API v1 (mobile apps)
  # --------------------------------------------------------
  namespace :api do
    namespace :v1 do
      post "auth/device",             to: "auth#device"
      get  "version-check",           to: "mobile_api#version_check"

      # Weather
      get "weather/index"
      get "weather/forecasts"
      get "weather/hourly"
      get "weather/radar"
      get "weather/period"
      get "weather/alerts"
      get "weather/sunrise_sunset"
      get "weather/discussion"
      get "weather/watches_fire_alerts"

      # Canyon Traveller
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

      # Home Resorts
      put "home_resorts",    to: "home_resorts#update"
      get "home_resorts",    to: "home_resorts#index"

      # Entitlements
      get "entitlements/index",    to: "entitlements#index"

      # Subscriptions
      post "iap/sync", to: "iap#sync"

      # Catch-all
      match "*unmatched",
            to: "base_mobile_api#render_not_found",
            via: :all
    end
  end

  # --------------------------------------------------------
  # MISC
  # --------------------------------------------------------
  resources :dabs, only: [ :index ]

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
