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
        response = parse_response(noaa_response)
        return failed("Unable to retrieve forecast for #{latitude}, #{longitude}") if response.nil?

        hourly = hourly_data(response["properties"]["forecastHourly"], latitude, longitude)
        return failed("Unable to retrieve hourly forecasts for #{latitude}, #{longitude}") if hourly.nil?

        hour_data =  hourly["properties"]["periods"].select { |period| period["startTime"] == start_time }.first
        successful({ "hour_data" => hour_data })
      end
    end
  end
end
