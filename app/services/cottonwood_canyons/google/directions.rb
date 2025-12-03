# app/services/cottonwood_canyons/google/directions.rb
module CottonwoodCanyons
  module Google
    class Directions < ApplicationService
      GOOGLE_DIRECTIONS_URL = "https://maps.googleapis.com/maps/api/directions/json"
      DEPARTURE_TIME = "now"
      TRAFFIC_MODEL  = "best_guess"
      MODE           = "driving"
      SERVICE_TYPE   = "Google Directions Service"

      def initialize(origin:, destination:)
        @origin = origin
        @destination = destination
      end

      def call
        response = google_directions
        body = response.body
        return failed("Empty response body") if body.blank?

        parsed = JSON.parse(body)
        parsed.symbolize_keys!
        successful(parsed[:routes])
      rescue => e
        Rails.logger.error("[#{SERVICE_TYPE}] Request failed: #{e.message}")
        failed(e.message)
      end

      private

      def parse_and_success(response_body)
        parsed = JSON.parse(response_body)
        parsed.symbolize_keys!
        successful(parsed[:routes])
      end

      def google_directions
        HTTParty.get(GOOGLE_DIRECTIONS_URL, query: {
          origin: @origin,
          destination: @destination,
          departure_time: DEPARTURE_TIME,
          traffic_model: TRAFFIC_MODEL,
          mode: MODE,
          key: ENV["GOOGLE_API_KEY"]
        })
      end
    end
  end
end
