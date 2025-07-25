module BaseForecaster
  extend ActiveSupport::Concern

  included do
    DUAL = "Dual Screen"
    SCREEN_A = "Locale A"
    SCREEN_B = "Locale B"

    DEFAULT_LAYER = "precipitation"

    def find_locations(location)
      return unless location
      location_context, _recent_locations = set_defaults
      location_services(location_context.location)
    end

    def location_services(location)
      location_service_result = OpenCage::GeoLocation::LocationFromInput.(location)
      locations = location_service_result.failure? ? [] : location_service_result.value[:locations]
      total = location_service_result.failure? ? 0 : location_service_result.value[:total]
      [ location_service_result.failure?,  locations, total ]
    end

    def summary_forecast_for_location(lat, long)
      service_result = Noaa::Forecast::Summary.(lat, long)
      [ service_result.failure?, service_result.value ]
    end

    def create_forecasts(latitude: 0, longitude: 0)
      service_result = Noaa::Forecast::TextOnly.(latitude, longitude)
      [ service_result.failure?, service_result.value["forecasts"] || service_result.value ]
    end

    def hourly_forecasts(latitude: 0, longitude: 0)
      service_result = Noaa::Forecast::HourlyForecast.(latitude, longitude)
      [ service_result.failure?, service_result.value["periods"] || service_result.value ]
    end

    def alert_forecasts(latitude: 0, longitude: 0)
      service_result = Noaa::Forecast::Alerts.(latitude, longitude)
      [ service_result.failure?, service_result || service_result.value ]
    end

    def fire_watch_and_alerts(latitude: 0, longitude: 0)
      service_result = Noaa::Forecast::WatchesAndAlerts.(latitude, longitude)
      [ service_result.failure?, service_result || service_result.value ]
    end

    def forecast_discussion(latitude: 0, longitude: 0)
      service_result = Noaa::Forecast::Discussion.(latitude, longitude)
      [ service_result.failure?, service_result || service_result.value ]
    end

    def period_forecasts(latitude: 0, longitude: 0, period: 0)
      service_result = Noaa::Forecast::Period.(latitude, longitude, period)
      [ service_result.failure?, service_result.value["period"] || service_result.value ]
    end

    def radar_for_locale(latitude: 0, longitude: 0)
      service_result = Noaa::Forecast::Radar.(latitude, longitude)
      [ service_result.failure?, service_result.value["radar"] || service_result.value ]
    end

    def set_defaults
      location_context = LocationContext.new(params)
      [ location_context, RecentLocations.new(session).add(location_context.to_h) ]
    end
  end
end
