# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module OpenWeather
  module Forecast
    class Hourly < Base
      SERVICE = ""

      def call
        query = {
          exclude: "minutely, daily, current, alerts",
          lat: @latitude,
          lon: @longitude,
          units: "metric"
        }
        url = "#{ENV.fetch("OPENWEATHER_ONE_CALL_API")}"
        response = weather_forecast(url: url, query: query, type: :hourly)
        return failed("No hourly forecast information available for lat: #{@latitude}, long: #{@longitude}") if response.nil?

        converted = Convert::Weather::OpenWeather::Hourly.call(response, get_overview)

        successful(converted)
      end

      private

      def get_overview
        overview_data = OpenWeather::Forecast::Overview.new(latitude: @latitude, longitude: @longitude).call
        return nil if overview_data.failure?

        overview_data.value["weather_overview"]
      end
    end
  end
end
