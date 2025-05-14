# frozen_string_literal: true

module Noaa
  module Forecast
    class Radar < Base

      def call
        response = parse_response(noaa_response)
        return failed("Unable to retrieve radar for #{latitude}, #{longitude}") if response.nil?
        radar = response["properties"]["radarStation"]
        successful({ radar: radar })
      end

    end
  end
end
