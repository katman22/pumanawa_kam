# lib/convert/weather/open_weather/forecast.rb
require_relative "../base_forecast"

module Convert
  module Weather
    module OpenWeather
      class Forecast < BaseForecast
        def self.call(raw_data, overview)
          daily = raw_data["daily"] || []

          daily.map.with_index do |period, index|
            standard_format(
              number: index.to_s,
              name: time_label_from_timestamp(period["dt"]),
              icon: openweather_icon_url(period.dig("weather", 0, "icon")),
              is_daytime: true, # Daily forecast assumes daytime
              temperature: period.dig("temp", "day").to_i,
              temperature_unit: "C", # or "F" depending on API units
              short_forecast: period.dig("weather", 0, "main") || "Forecast",
              detailed_forecast: get_description(period, index, overview),
              wind_speed: "#{period["wind_speed"].to_i} m/s",
              wind_direction: degrees_to_cardinal(period["wind_deg"]),
              start_time: Time.at(period["dt"]).iso8601,
              dewpoint: {
                unitCode: "unit:degC", # adjust for unit system
                value: period["dew_point"]
              },
              relative_humidity: {
                unitCode: "unit:percent",
                value: period["humidity"]
              },
              probability_of_precipitation: {
                unitCode: "unit:percent",
                value: (period["pop"].to_f * 100).round
              }
              # raw: period
            )
          end
        end

        def self.time_label_from_timestamp(timestamp)
          Time.at(timestamp).strftime("%A") # e.g. "Monday"
        end

        def self.openweather_icon_url(icon_code)
          "https://openweathermap.org/img/wn/#{icon_code}@2x.png"
        end

        def self.get_description(period, index, overview)
          return overview if index == 0
          period.dig("weather", 0, "description") || "No details"
        end

        def self.degrees_to_cardinal(degrees)
          return "" if degrees.nil?
          directions = %w[N NNE NE ENE E ESE SE SSE S SSW SW WSW W WNW NW NNW]
          index = ((degrees % 360) / 22.5).round
          directions[index % 16]
        end
      end
    end
  end
end
