# lib/convert/weather/noaa/forecast.rb
require_relative "../base_forecast"

module Convert
  module Weather
    module Noaa
      class Forecast < BaseForecast
        def self.call(raw_data)
          periods = raw_data.dig("properties", "periods") || []

          periods.map do |period|
            standard_format(
              number: period["number"],
              name: period["name"],
              icon: period["icon"],
              is_daytime: period["isDaytime"],
              temperature: period["temperature"],
              temperature_unit: period["temperatureUnit"],
              short_forecast: period["shortForecast"],
              detailed_forecast: period["detailedForecast"],
              wind_speed: period["windSpeed"],
              wind_direction: period["windDirection"],
              start_time: period["startTime"],
              dewpoint: extract_quantity(period["dewpoint"]),
              relative_humidity: extract_quantity(period["relativeHumidity"]),
              probability_of_precipitation: extract_quantity(period["probabilityOfPrecipitation"])
            )
          end
        end

        def self.extract_quantity(field)
          return { unitCode: "", value: nil } unless field.is_a?(Hash)
          {
            unitCode: field["unitCode"] || "",
            value: field["value"]
          }
        end
      end
    end
  end
end
