# frozen_string_literal: true

module CottonwoodCanyons
  class TravelTime
    GOOGLE_DIRECTIONS_URL = "https://maps.googleapis.com/maps/api/directions/json"

    def initialize(origin:, destination:)
      @origin = origin
      @destination = destination
    end

    def call
      response = HTTParty.get(GOOGLE_DIRECTIONS_URL, {
        query: {
          origin: @origin,
          destination: @destination,
          departure_time: "now",
          key: ENV["GOOGLE_API_KEY"]
        }
      })
      json = JSON.parse(response.body)
      leg = json.dig("routes", 0, "legs", 0)

      {
        duration_seconds: leg.dig("duration_in_traffic", "value"),
        human_readable: leg.dig("duration_in_traffic", "text")
      }
    rescue => e
      Rails.logger.error("CanyonTravelTimeService failed: #{e.message}")
      { error: "Could not fetch travel time" }
    end
  end
end
