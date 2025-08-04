# frozen_string_literal: true

module Noaa
  module Forecast
    class HourlyForecast < Base
      CACHE_KEY = "noaa-forecast-hourly-forecast"

      def call
        response = noaa_response
        return failed("Unable to retrieve forecast for #{latitude}, #{longitude}") if response.nil?

        forecast = forecast_response(response)
        return failed("Unable to retrieve forecast for #{latitude}, #{longitude}") if forecast.nil?

        hourly = hourly_data(response["properties"]["forecastHourly"], latitude, longitude)
        return failed("Unable to retrieve hourly forecasts for #{latitude}, #{longitude}") if hourly.nil?
        hourly_periods = merge_first_record(forecast, hourly)

        converted = Convert::Weather::Noaa::Hourly.(hourly_periods)
        successful({ "periods" => converted })
      end

      def cache_key(key)
        "#{key}_#{rounded(latitude)}_#{rounded(longitude)}"
      end

      def rounded(value)
        value.to_f.round(4)
      end

      def merge_first_record(forecast, hourly)
        hourly["properties"]["periods"][0] = forecast["properties"]["periods"][0]
        hourly["properties"]["periods"][0]["icon"] = hourly["properties"]["periods"][0]["icon"].gsub("size=medium", "size=large")
        hourly["properties"]["periods"][0..98]
      end
    end
  end
end
