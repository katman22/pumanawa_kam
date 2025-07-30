# lib/location_converter/maptiler.rb

module Convert
  module Geolocation
    class Google < Base
      def call
        results = raw_data["results"] || []

        results.map do |result|
          address_components = result["address_components"] || []
          location = result.dig("geometry", "location") || {}

          country = extract_component(address_components, "country")
          country_code = extract_component(address_components, "country", short: true)
          place_name = result["formatted_address"]

          standard_format(
            lat: location["lat"],
            long: location["lng"],
            country: country,
            country_code: country_code,
            name: place_name
          )
        end
      end

      def extract_component(components, type, short: false)
        found = components.find { |comp| comp["types"].include?(type) }
        return nil unless found

        short ? found["short_name"] : found["long_name"]
      end
    end
  end
end
