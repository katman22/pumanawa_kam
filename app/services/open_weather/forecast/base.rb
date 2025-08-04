# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "httparty"

module OpenWeather
  module Forecast
    class Base < ApplicationService
      include HTTParty

      def initialize(latitude:, longitude:, date: nil, clear_cache: false, period: 0)
        @date = date
        @latitude = latitude
        @longitude = longitude
        @clear_cache = clear_cache
        @period = period
      end

      def call
        # Not Implemented
      end

      def weather_forecast(url:, query: {}, type: "default")
        api_key = ENV.fetch("OPENWEATHER_API_KEY")
        lat_lng_key = "#{@latitude}#{@longitude}"
        cache_key = "openweather_#{url}_#{lat_lng_key}_#{type}"
        Rails.cache.delete(cache_key) if @clear_cache

        Rails.cache.fetch(cache_key, expires_in: 30.minutes.to_i) do
          response = HTTParty.get(url, {
            query: query.merge(appid: api_key)
          })
          parse_response(response)
        end
      end

      def parse_response(response)
        return nil if response.body.nil? || response.body.empty? || response["status"] == 404
        JSON.parse(response.body)
      end
    end
  end
end
