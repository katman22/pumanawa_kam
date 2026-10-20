# frozen_string_literal: true

module Noaa
  module Forecast
    class Point < ApplicationService
      def initialize(latitude:, longitude:)
        @latitude, @longitude = latitude, longitude
      end

      def call
        lat, lon = Float(@latitude), Float(@longitude)
        return failed(code: "invalid_coordinates") unless lat.finite? && lon.finite? && lat.between?(-90, 90) && lon.between?(-180, 180)

        result = Noaa::Request.call(url: "https://api.weather.gov/points/#{lat},#{lon}")
        return result if result.failure?

        properties = result.value.dig("body", "properties")
        return failed(code: "invalid_point") unless properties.is_a?(Hash)

        required = %w[cwa gridId gridX gridY forecastGridData forecast forecastHourly forecastZone county fireWeatherZone timeZone]
        return failed(code: "invalid_point") unless required.all? { |key| properties.key?(key) && !properties[key].nil? }
        return failed(code: "invalid_point") unless properties["gridId"].to_s.match?(/\A[A-Z]{3}\z/) && %w[gridX gridY].all? { |key| properties[key].is_a?(Integer) && properties[key] >= 0 }
        urls = %w[forecastGridData forecast forecastHourly forecastZone county fireWeatherZone]
        return failed(code: "invalid_point") unless urls.all? { |key| Noaa::Request.valid_url?(properties[key]) }
        expected = "https://api.weather.gov/gridpoints/#{properties['gridId']}/#{properties['gridX']},#{properties['gridY']}"
        return failed(code: "invalid_point") unless properties["forecastGridData"] == expected

        successful(properties.slice(*required, "radarStation").merge("latitude" => lat, "longitude" => lon))
      rescue ArgumentError, TypeError
        failed(code: "invalid_coordinates")
      end
    end
  end
end
