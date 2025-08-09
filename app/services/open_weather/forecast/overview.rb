# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "httparty"

module OpenWeather
  module Forecast
    class Overview < Base
      SERVICE = "overview"

      def call
        query = {
          date: @date.nil? ? nil : @date.strftime("%Y-%m-%d"),
          units: @units,
          lat: @latitude,
          lon: @longitude
        }
        url= "#{ENV.fetch("OPENWEATHER_ONE_CALL_API")}/#{SERVICE}"
        response = weather_forecast(url: url, query: query)
        return failed("No weather information available for lat: #{@latitude}, long: #{@longitude}") if response.nil?

        successful(response)
      end
    end
  end
end
