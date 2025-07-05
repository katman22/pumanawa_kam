# frozen_string_literal: true

module CottonwoodCanyons
  module Google
    class Directions < ApplicationService
      GOOGLE_DIRECTIONS_URL = "https://maps.googleapis.com/maps/api/directions/json"
      DEPARTURE_TIME = "now"
      TRAFFIC_MODEL = "best_guess"
      SERVICE_TYPE = "Google Directions Service"
      FAILED_MESSAGE = ->(message) { " #{message}" }

      def initialize(origin:, destination:)
        @origin = origin
        @destination = destination
      end

      def call
        response = google_directions
        return nil if response.nil? || response["status"] == 404

        response = JSON.parse(response.body)
        response.symbolize_keys!
        successful(response[:routes])
      rescue => e
        Rails.logger.error("Google Directions Service failed: #{e.message}")
        failed(FAILED_MESSAGE.call(e.message))
      end

      def google_directions
        HTTParty.get(GOOGLE_DIRECTIONS_URL, {
          query: {
            origin: @origin,
            destination: @destination,
            departure_time: DEPARTURE_TIME,
            traffic_model: TRAFFIC_MODEL,
            key: ENV["GOOGLE_API_KEY"]
          }
        })
      end

    end
  end
end
