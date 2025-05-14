# frozen_string_literal: true

module Noaa
  module Forecast
    class HourlyForecast < Base
      def call
        response = parse_response(noaa_response)
        return failed("Unable to retrieve forecast for #{latitude}, #{longitude}") if response.nil?

        forecast = parse_response(forecast_response(response))
        return failed("Unable to retrieve forecast for #{latitude}, #{longitude}") if forecast.nil?

        hourly = hourly_data(response["properties"]["forecastHourly"])
        return failed("Unable to retrieve hourly forecasts for #{latitude}, #{longitude}") if hourly.nil?
        hourly["properties"]["periods"][0] = forecast["properties"]["periods"][0]
        hourly["properties"]["periods"][0]["icon"] = hourly["properties"]["periods"][0]["icon"].gsub("size=medium", "size=large")
        successful({ "periods" => hourly["properties"]["periods"][0..23] })
      end
    end
  end
end
