# frozen_string_literal: true

module Noaa
  module Forecast
    class Period < Base
      attr_reader :period

      def initialize(latitude, longitude, period)
        @period = period
        super(latitude, longitude)
      end

      def call
        response = parse_response(noaa_response)
        return failed("Unable to retrieve forecast for #{latitude}, #{longitude}") if response.nil?

        forecast = parse_response(forecast_response(response))
        return failed("Unable to retrieve forecast for #{latitude}, #{longitude}") if forecast.nil?

        period_forecast = forecast_for_period(forecast, period)
        return failed("Current forecast for #{latitude}, #{longitude} is unavailable") if period_forecast.first.nil?

        returned_period = merge_hour_with_period(period_forecast.first)
        converted = Convert::Weather::Noaa::Hourly.([ returned_period ])
        successful({ "period" => converted, "latitude" => latitude, "longitude" => longitude, "from_cache" => from_cache })
      end

      def merge_hour_with_period(period)
        hour_data = ::Noaa::Forecast::HourForecast.(latitude, longitude, period["startTime"])
        period.merge!("dewpoint"=> hour_data.value["hour_data"]["dewpoint"], "relativeHumidity" => hour_data.value["hour_data"]["relativeHumidity"])
      end
    end
  end
end
