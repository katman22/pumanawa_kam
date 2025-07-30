# frozen_string_literal: true

module Noaa
  module Forecast
    class Base < ApplicationService
      attr_reader :latitude, :longitude, :from_cache

      BASE_NOAA_URL = "https://api.weather.gov/points/"

      def initialize(latitude, longitude)
        @latitude = latitude
        @longitude = longitude
        @from_cache = false
      end

      def call
        # Not implemented
      end

      def forecast_response(response)
        return nil if response.nil? || response["status"] == 404
        lat_lng_key = "#{response["geometry"]["coordinates"].first}#{response["geometry"]["coordinates"][1]}"
        cache_key = "noaa_forecasts_#{lat_lng_key}"
        Rails.cache.fetch(cache_key, expires_in: 30.minutes.to_i) do
          HTTParty.get(forecast_url(response), headers: noaa_agent_header)
        end
      end

      def high_low(forecast, current)
        next_forecast = forecast["properties"]["periods"].select { |rows| rows["number"] == 2 }.first
        current["isDaytime"] ? [ current["temperature"], next_forecast["temperature"] ] : [ next_forecast["temperature"], current["temperature"] ]
      end

      def forecast_url(response)
        response["properties"]["forecast"]
      end

      def parse_response(response)
        return nil if response.body.nil? || response.body.empty? || response["status"] == 404
        JSON.parse(response)
      end

      def all_forecasts(forecast)
        Convert::Weather::Noaa::Forecast.call(forecast)
      end

      def forecast_for_period(forecast, period_number)
        forecast["properties"]["periods"].select { |period| period["number"] == period_number.to_i }
      end

      def noaa_response
        lat_lng_key = "#{@latitude}#{@longitude}"
        cache_key = "noaa_#{lat_lng_key}"
        Rails.cache.fetch(cache_key, expires_in: 30.minutes.to_i) do
          HTTParty.get(noaa_url, headers: noaa_agent_header)
        end
      end

      def hourly_data(url, latitude, longitude)
        lat_lng_key = "#{latitude}#{longitude}"
        cache_key = "noaa_hourly#{lat_lng_key}"
        @from_cache = true

        Rails.cache.fetch(cache_key, expires_in: 30.minutes.to_i) do
          @from_cache = false
          response = HTTParty.get(url, headers: noaa_agent_header)
          parse_response(response)
        end
      end

      def noaa_agent_header
        { "User-Agent" => "aura_weather (#{ENV['APPLICATION_EMAIL']})" }
      end

      def noaa_url
        "#{BASE_NOAA_URL}#{latitude},#{longitude}"
      end

      def cache_key(key)
        "#{key}_#{rounded(latitude)}_#{rounded(longitude)}"
      end

      def rounded(value)
        value.to_f.round(4)
      end
    end
  end
end
