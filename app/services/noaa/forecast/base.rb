# frozen_string_literal: true

module Noaa
  module Forecast
    class Base < ApplicationService
      attr_reader :latitude, :longitude, :zipcode, :from_cache

      BASE_NOAA_URL = "https://api.weather.gov/points/"

      def initialize(latitude, longitude, zipcode)
        @latitude = latitude
        @longitude = longitude
        @zipcode = zipcode
        @from_cache = false
      end

      def call
        # Not implemented
      end

      def forecast_response(response)
        return nil if response.nil? || response["status"] == 404
        HTTParty.get(forecast_url(response), headers: noaa_agent_header)
      end

      def high_low(forecast, current)
        next_forecast = forecast["properties"]["periods"].select { |rows| rows["number"] == 2 }.first
        current["isDaytime"] ? [ current["temperature"], next_forecast["temperature"] ] : [ next_forecast["temperature"], current["temperature"] ]
      end

      def forecast_url(response)
        response["properties"]["forecast"]
      end

      def parse_response(response)
        return nil if response.nil? || response["status"] == 404
        JSON.parse(response)
      end

      def noaa_response
        lat_lng_key = "#{@latitude}#{@longitude}".delete(".-")
        cache_key = "noaa_#{lat_lng_key}"
        cached_response = Rails.cache.read(cache_key)

        if cached_response
          @from_cache = true
          return cached_response
        end

        response = HTTParty.get(noaa_url, headers: noaa_agent_header)
        Rails.cache.write(cache_key, response, expires_in: 30.minutes)
        response
      end

      def noaa_agent_header
        { "User-Agent" => "my_weather_forecaster (#{ENV['APPLICATION_EMAIL']})" }
      end

      def noaa_url
        "#{BASE_NOAA_URL}#{latitude},#{longitude}"
      end
    end
  end
end
