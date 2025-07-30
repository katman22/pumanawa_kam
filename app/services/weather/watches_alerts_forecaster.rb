# app/services/forecast_converter.rb

module Weather
  class WatchesAlertsForecaster < ApplicationService
    attr_reader :provider, :longitude, :latitude

    def initialize(provider, latitude, longitude)
      @provider = provider
      @latitude = latitude
      @longitude = longitude
    end

    def call
      forecasts = case provider.to_s.downcase
      when "noaa"
                    Noaa::Forecast::WatchesAndAlerts.(latitude, longitude)
      else
                    OpenWeather::Forecast::WatchesAndAlerts.(latitude, longitude)
      end
      return failed "#{forecasts.value}" if forecasts.failure?

      successful forecasts.value
    end
  end
end
