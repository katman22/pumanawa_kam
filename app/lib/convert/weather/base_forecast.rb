# lib/convert/weather/base_forecast.rb
module Convert
  module Weather
    class BaseForecast
      def self.call(_raw_data)
        raise NotImplementedError, "Subclasses must implement .call"
      end

      def self.standard_format(
        number:,
        name:,
        icon:,
        is_daytime:,
        temperature:,
        temperature_unit:,
        short_forecast:,
        detailed_forecast:,
        wind_speed:,
        wind_direction:,
        start_time:,
        dewpoint:,
        relative_humidity:,
        probability_of_precipitation:
        # raw: nil
      )
        {
          number: number.to_s,
          name: name,
          icon: icon,
          isDaytime: is_daytime,
          temperature: temperature,
          temperatureUnit: temperature_unit,
          shortForecast: short_forecast,
          detailedForecast: detailed_forecast,
          windSpeed: wind_speed,
          windDirection: wind_direction,
          startTime: start_time,
          dewpoint: dewpoint,
          relativeHumidity: relative_humidity,
          probabilityOfPrecipitation: probability_of_precipitation
          # raw: raw
        }
      end
    end
  end
end
