# frozen_string_literal: true

module Noaa
  module Alerts
    class Fetch < ApplicationService
      def initialize(latitude:, longitude:)
        @latitude, @longitude = latitude, longitude
      end

      def call
        lat, lon = Float(@latitude), Float(@longitude)
        return failed(code: "invalid_coordinates") unless lat.finite? && lon.finite? && lat.between?(-90, 90) && lon.between?(-180, 180)

        url = "https://api.weather.gov/alerts?active=true&point=#{lat},#{lon}"
        features, seen = [], []
        while url
          return failed(code: "alert_pagination_invalid") if seen.include?(url) || seen.size >= 10 || !Noaa::Request.valid_url?(url)

          seen << url
          result = Noaa::Request.call(url: url)
          return result if result.failure?
          body = result.value["body"]
          return failed(code: "invalid_alert_collection") unless body.is_a?(Hash) && body["features"].is_a?(Array) && body["features"].all? { |item| item.is_a?(Hash) && item["properties"].is_a?(Hash) }

          features.concat(body["features"])
          pagination = body["pagination"]
          return failed(code: "alert_pagination_invalid") unless pagination.nil? || pagination.is_a?(Hash)

          url = pagination&.fetch("next", nil)
        end
        successful("features" => features)
      rescue ArgumentError, TypeError
        failed(code: "invalid_coordinates")
      end
    end
  end
end
