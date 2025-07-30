# lib/location_converter/base.rb
module Convert
  module Geolocation
    class Base
        attr_reader :raw_data

        def initialize(raw_data:)
          @raw_data = raw_data
        end

        def call
          raise NotImplementedError, "Override in subclass"
        end

        def standard_format(lat:, long:, country:, country_code:, name:, raw: nil)
          {
            lat: lat.to_f,
            lng: long.to_f,
            country: country.to_s,
            country_code: country_code.to_s.downcase,
            name: name.to_s
          }
        end
    end
  end
end
