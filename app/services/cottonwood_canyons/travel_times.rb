# frozen_string_literal: true

module CottonwoodCanyons
  class TravelTimes < CottonwoodCanyons::TravelBase

    TRAVEL_ERROR = "No travel data available currently."

    def initialize(resort:)
      @origin      = resort.departure_point
      @destination = resort.location
      @resort      = resort
    end

    def call
      to_resp   = Google::DirectionsFetcher.call(origin: @origin, destination: @destination, expires_in: dynamic_ttl)
      from_resp = Google::DirectionsFetcher.call(origin: @destination, destination: @origin, expires_in: dynamic_ttl)

      result = {
        resort:           @resort.resort_name,
        to_resort:        extract_duration(to_resp),
        from_resort:      extract_duration(from_resp),
        departure_point:  @resort.departure_point,
        overview_polyline: extract_polyline(to_resp),
        updated_at:       Time.current.strftime("%a %l:%M"),
      }

      successful(result)
    rescue => e
      Rails.logger.error("CanyonTravelTimeService failed: #{e.class}: #{e.message}")
      failed(TRAVEL_ERROR)
    end

  end
end
