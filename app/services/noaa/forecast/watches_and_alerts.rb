# frozen_string_literal: true

module Noaa
  module Forecast
    class WatchesAndAlerts < Base
      WEATHER_PRODUCTS = ->(office) { "https://api.weather.gov/products/types/AFD/locations/#{office}" }

      def initialize(latitude, longitude)
        @latitude = latitude
        @longitude = longitude
      end

      def call
        alert_result = Noaa::Forecast::Alerts.(latitude, longitude)
        discussion_result = Noaa::Forecast::Discussion.(latitude, longitude)

        watches_and_alerts = {
          alerts: alert_result.value["alerts"],
          fire_weather: discussion_result.value[:fire_weather],
          watches_warnings: discussion_result.value[:watches_warnings]
        }

        successful(watches_and_alerts)
      end


    end
  end
end
