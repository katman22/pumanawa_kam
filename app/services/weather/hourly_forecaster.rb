# app/services/forecast_converter.rb

module Weather
  class HourlyForecaster < ApplicationService
    attr_reader :provider, :longitude, :latitude

    def initialize(provider, latitude, longitude)
      @provider = provider
      @latitude = latitude
      @longitude = longitude
    end

    def call
      forecasts = case provider.to_s.downcase
      when "noaa"
                    Noaa::Forecast::HourlyForecast.(latitude, longitude)
      else
                    "openweather"
                    OpenWeather::Forecast::Hourly.new(latitude: latitude, longitude: longitude).call
      end
      return failed "#{forecasts.value}" if forecasts.failure?

      successful forecasts.value
    end
  end
end
