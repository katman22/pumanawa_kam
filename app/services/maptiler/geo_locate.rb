# frozen_string_literal: true

require "httparty"

module Maptiler
  class GeoLocate < ApplicationService
    BASE_URL = "https://api.maptiler.com/geocoding"

    def initialize(location)
      @location = location
      @api_key = ENV.fetch("MAP_TILER", nil)
    end

    def call
      return failed("Missing location input") unless @location.present?
      return failed("Missing MapTiler API key") unless @api_key

      Rails.cache.fetch(cache_key, expires_in: 12.hours) do
        response = HTTParty.get("#{BASE_URL}/#{URI.encode_www_form_component(@location)}.json", query: {
          key: @api_key
        })

        if response.success?
          successful(response.parsed_response)
        else
          failed("MapTiler geocoding failed: #{response.code} - #{response.body}")
        end
      end
    end

    private

    def cache_key
      "maptiler_geocode_#{Digest::SHA256.hexdigest(@location)}"
    end
  end
end
