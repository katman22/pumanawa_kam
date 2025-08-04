# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module OpenWeather
  module Forecast
    class Alerts < Base
      SERVICE = ""

      def call
        query = {
          exclude: "minutely, daily, current, hourly",
          lat: @latitude,
          lon: @longitude,
          units: "metric"
        }
        url = "#{ENV.fetch("OPENWEATHER_ONE_CALL_API")}"
        response = weather_forecast(url: url, query: query, type: :hourly)
        return failed("No Alert information available for lat: #{@latitude}, long: #{@longitude}") if response.nil?

        converted = Convert::Weather::OpenWeather::Alerts.call(response)

        successful({ "alerts" => converted })
      end
    end
  end
end
