# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module OpenWeather
  module Forecast
    class Period < Base
      SERVICE = ""

      def call
        response = OpenWeather::Forecast::Hourly.new(latitude: @latitude, longitude: @longitude).call
        return failed(response.value) if response.failure?

        returned_period = forecast_for_period(response.value, @period)
        successful({ "period" => returned_period, "latitude" => @latitude, "longitude" => @longitude, "from_cache" => @clear_cache })
      end

      private

      def forecast_for_period(forecast, period_number)
        forecast.select { |period| period[:number] == period_number }
      end
    end
  end
end
