# frozen_string_literal: true

require "httparty"

module Google
  class GeoLocate < ApplicationService
    BASE_URL = "https://maps.googleapis.com/maps/api/geocode/json"

    def initialize(location)
      @location = location
      @api_key = ENV.fetch("GOOGLE_GEO_LOCATE", nil)
    end

    def call
      return failed("Missing location input") unless @location.present?
      return failed("Missing Google API key") unless @api_key

      Rails.cache.fetch(cache_key, expires_in: 12.hours) do
        response = HTTParty.get(BASE_URL, query: {
          address: @location,
          key: @api_key
        })

        if response.success?
          locations = format_locations(response.parsed_response)
          successful(locations)
        else
          failed("Google geocoding failed: #{response.code} - #{response.body}")
        end
      end
    end

    private

    def format_locations(locations)
      Convert::Geolocation::Google.new(raw_data: locations).call
    end

    def cache_key
      "google_geocode_#{Digest::SHA256.hexdigest(@location)}"
    end
  end
end
