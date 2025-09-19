# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "httparty"

module SunriseSunset
  class Times < ApplicationService
    include HTTParty

    def initialize(timezone:, latitude:, longitude:)
      @timezone = timezone
      @latitude = latitude
      @longitude = longitude
    end

    def call
      dusk_dawn
    end

    def dusk_dawn
      lat_lng_key = "#{@latitude}#{@longitude}"
      cache_key = "sunrise_sunset_#{lat_lng_key}"
      url = "https://api.sunrisesunset.io/json"
      Rails.cache.fetch(cache_key, expires_in: 720.minutes.to_i) do
        response = HTTParty.get(url, {
          query: { timezone: @timezone, lat: @latitude, lng: @longitude }
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
