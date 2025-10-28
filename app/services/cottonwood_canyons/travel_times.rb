# frozen_string_literal: true

module CottonwoodCanyons
  class TravelTimes
    attr_reader :resort

    TRAVEL_ERROR = "No travel data available currently."

    def initialize(resort:)
      @origin      = resort.departure_point
      @destination = resort.location
      @resort      = resort
    end

    def call
      # Use cached wrapper (5-min bucket by default)
      to_resp   = CottonwoodCanyons::Google::DirectionsFetcher.call(origin: @origin,      destination: @destination)
      from_resp = CottonwoodCanyons::Google::DirectionsFetcher.call(origin: @destination, destination: @origin)

      {
        resort:           resort.resort_name,
        to_resort:        extract_duration(to_resp),
        from_resort:      extract_duration(from_resp),
        departure_point:  resort.departure_point,
        overview_polyline: extract_polyline(to_resp), # use the "to" route for the map
        updated_at:       Time.current.strftime("%a %l:%M")
      }
    rescue => e
      Rails.logger.error("CanyonTravelTimeService failed: #{e.class}: #{e.message}")
      { error: TRAVEL_ERROR }
    end

    private

    def extract_duration(response)
      return "N/A" unless response&.success? && response.value.present?

      route = response.value.first
      legs  = route && (route["legs"] || route[:legs])
      leg   = legs&.first
      return "N/A" unless leg

      leg = leg.transform_keys { |k| k.to_s.to_sym }
      if leg[:duration_in_traffic].is_a?(Hash)
        dit = leg[:duration_in_traffic].transform_keys { |k| k.to_s.to_sym }
        txt = dit[:text].to_s
        return txt.gsub("mins", "").strip
      end

      (leg.dig(:duration, :text) || TRAVEL_ERROR).to_s
    end

    def extract_polyline(response)
      return nil unless response&.success? && response.value.present?
      route = response.value.first
      poly  = route && (route["overview_polyline"] || route[:overview_polyline])
      poly && (poly["points"] || poly[:points])
    end

    def resort
      @resort
    end
  end
end
