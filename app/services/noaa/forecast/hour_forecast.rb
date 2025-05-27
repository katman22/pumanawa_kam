# frozen_string_literal: true

module Noaa
  module Forecast
    class HourForecast < Base
      CACHE_KEY = "noaa-hour-data"
      attr_reader :start_time

      def initialize(latitude, longitude, start_time)
        @start_time = start_time
        super(latitude, longitude)
      end

      def call
        # cached_response = Rails.cache.read(cache_key(CACHE_KEY))
        # return successful({ "hour_data" => cached_response }) if cached_response.present?

        response = parse_response(noaa_response)
        return failed("Unable to retrieve forecast for #{latitude}, #{longitude}") if response.nil?

        hourly = hourly_data(response["properties"]["forecastHourly"])
        return failed("Unable to retrieve hourly forecasts for #{latitude}, #{longitude}") if hourly.nil?

        hour_data =  hourly["properties"]["periods"].select { |period| period["startTime"] == start_time }.first

        Rails.cache.write(cache_key(CACHE_KEY), hour_data, expires_in: 45.minutes)
        successful({ "hour_data" => hour_data })
      end
    end
  end
end
