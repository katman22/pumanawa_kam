# app/services/forecast_converter.rb

module Weather
  class PeriodForecaster < ApplicationService
    attr_reader :provider, :longitude, :latitude, :period

    def initialize(provider, latitude, longitude, period)
      @provider = provider
      @latitude = latitude
      @longitude = longitude
      @period = period
    end

    def call
      forecasts = case provider.to_s.downcase
      when "noaa"
                    Noaa::Forecast::Period.(latitude, longitude, period)
      else "openweather"
                    OpenWeather::Forecast::Period.new(latitude: latitude, longitude: longitude, period: period).call
      end
      return failed "#{forecasts.value}" if forecasts.failure?

      successful({ "period"=> forecasts.value["period"].first })
    end
  end
end
