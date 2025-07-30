# frozen_string_literal: true

module OpenWeather
  module Forecast
    class WatchesAndAlerts < ApplicationService
      WEATHER_PRODUCTS = ->(office) { "https://api.weather.gov/products/types/AFD/locations/#{office}" }

      def initialize(latitude, longitude)
        @latitude = latitude
        @longitude = longitude
      end

      def call
        discussion_result = OpenWeather::Forecast::Discussion.new(latitude: @latitude, longitude: @longitude).call
        return failed(discussion_result.value) if discussion_result.failure?

        watches_and_alerts = {
          alerts: discussion_result.value["alerts"] || "",
          fire_weather: "",
          watches_warnings: discussion_result.value[:watches_warnings]
        }

        successful(watches_and_alerts)
      end
    end
  end
end
