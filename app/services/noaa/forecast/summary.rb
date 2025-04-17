# frozen_string_literal: true

module Noaa
  module Forecast
    class Summary < Base
      def call
        response = parse_response(noaa_response)
        return failed("Unable to retrieve forecast for #{latitude}, #{longitude}") if response.nil?

        forecast = parse_response(forecast_response(response))
        return failed("Unable to retrieve forecast for #{latitude}, #{longitude}") if forecast.nil?

        current = current_forecast(forecast)
        return failed("Current forecast for #{latitude}, #{longitude} is unavailable") if current.nil?

        high, low = high_low(forecast, current)
        successful(current.merge("high" => high, "low" => low, "latitude" => latitude, "longitude" => longitude, "from_cache" => from_cache))
      end

      def current_forecast(forecast)
        forecast["properties"]["periods"].select { |rows| rows["number"] == 1 }.first
      end
    end
  end
end
