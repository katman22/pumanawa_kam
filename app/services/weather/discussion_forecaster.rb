# app/services/forecast_converter.rb

module Weather
  class DiscussionForecaster < ApplicationService
    attr_reader :provider, :longitude, :latitude, :units

    def initialize(provider, latitude, longitude, units = "metric")
      @provider = provider
      @latitude = latitude
      @longitude = longitude
      @units = units
    end

    def call
      forecasts = case provider.to_s.downcase
      when "noaa"
                    Noaa::Forecast::Discussion.(latitude, longitude)
      else
                    "openweather"
                    OpenWeather::Forecast::Discussion.new(latitude: latitude, longitude: longitude, units: units).call
      end
      return failed "#{forecasts.value}" if forecasts.failure?

      successful forecasts.value
    end
  end
end
