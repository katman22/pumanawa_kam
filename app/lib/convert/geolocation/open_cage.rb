# lib/location_converter/maptiler.rb

module Convert
  module Geolocation
    class OpenCage < Base
      def call
        locations = raw_data || []
        locations.map do |location|
          components = location["components"] || {}
          coords = location["geometry"] || {}

          standard_format(
            lat: coords["lat"],
            long: coords["lng"],
            country: components["country"],
            country_code: components["country_code"],
            name: location["formatted"] || components["city"] || "Unknown"
          )
        end
      end
    end
  end
end
