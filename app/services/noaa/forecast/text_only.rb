# frozen_string_literal: true

module Noaa
  module Forecast
    class TextOnly < Base
      def call
        response = parse_response(noaa_response)
        return failed("Unable to retrieve forecast for #{latitude}, #{longitude}") if response.nil?

        forecast = parse_response(forecast_response(response))
        return failed("Unable to retrieve forecast for #{latitude}, #{longitude}") if forecast.nil?

        forecasts = all_forecasts(forecast)
        return failed("Current forecast for #{latitude}, #{longitude} is unavailable") if forecasts.nil?

        high, low = high_low(forecast, forecasts.first)
        successful({ "forecasts" => forecasts, "latitude" => latitude, "longitude" => longitude, "from_cache" => from_cache, "high" => high, "low" => low })
      end

      def all_forecasts(forecast)
        forecast["properties"]["periods"]
      end
    end
  end
end
