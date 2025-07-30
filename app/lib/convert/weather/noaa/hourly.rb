# lib/convert/weather/noaa/hourly.rb
require_relative "../base_forecast"

module Convert
  module Weather
    module Noaa
      class Hourly < BaseForecast
        def self.call(raw_data)
          periods = raw_data

          periods.map do |period|
            standard_format(
              number: period["number"],
              name: label_for(period),
              icon: period["icon"],
              is_daytime: period["isDaytime"],
              temperature: period["temperature"],
              temperature_unit: period["temperatureUnit"],
              short_forecast: period["shortForecast"] || "No summary",
              detailed_forecast: fallback_detailed(period),
              wind_speed: period["windSpeed"] || "",
              wind_direction: period["windDirection"] || "",
              start_time: period["startTime"],
              dewpoint: extract_quantity(period["dewpoint"]),
              relative_humidity: extract_quantity(period["relativeHumidity"]),
              probability_of_precipitation: extract_quantity(period["probabilityOfPrecipitation"])
              # raw: period
            )
          end
        end

        def self.label_for(period)
          return period["name"] unless period["startTime"].to_s.strip.empty?
          DateTime.parse(period["startTime"]).strftime("%A, %b%e")
        rescue
          "Hourly"
        end

        def self.fallback_detailed(period)
          detail = period["detailedForecast"]
          return detail unless detail.to_s.strip.empty?
          period["shortForecast"] || "Forecast not available"
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
