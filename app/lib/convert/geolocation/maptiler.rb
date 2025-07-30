# lib/location_converter/maptiler.rb

module Convert
  module Geolocation
    class Maptiler < Base
      def call
        features = raw_data["features"] || []

        features.map do |feature|
          props = feature["properties"] || {}
          coords = feature.dig("geometry", "coordinates") || []
          context = feature["context"] || []

          country_info = context.find { |c| c["id"]&.start_with?("country.") }
          country_name = country_info&.dig("text")
          country_code = country_info&.dig("country_code") || props["country_code"]

          place_name = feature["place_name"] || "Unknown"

          standard_format(
            lat: coords[1],
            long: coords[0],
            country: country_name,
            country_code: country_code,
            name: place_name
          )
        end
      end
    end
  end
end
