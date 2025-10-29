# app/services/cottonwood_canyons/google/directions.rb
module CottonwoodCanyons
  module Google
    class Directions < ApplicationService
      GOOGLE_DIRECTIONS_URL = "https://maps.googleapis.com/maps/api/directions/json"
      DEPARTURE_TIME = "now"
      TRAFFIC_MODEL  = "best_guess"
      MODE           = "driving"
      SERVICE_TYPE   = "Google Directions Service"
      CACHE_SECONDS  = 300 # 5 minutes

      def initialize(origin:, destination:)
        @origin = origin
        @destination = destination
      end

      def call
        key = DirectionsKey.key_for(@origin, @destination, traffic_model: TRAFFIC_MODEL, mode: MODE)

        if (cached = Rails.cache.read(key))
          Rails.logger.info("[#{SERVICE_TYPE}] Cache hit for #{key}")
          return parse_and_success(cached)
        end

        Rails.logger.info("[#{SERVICE_TYPE}] Cache miss for #{key}, calling Google API…")

        response_body = Rails.cache.fetch(
          key,
          expires_in: CACHE_SECONDS.seconds,
          race_condition_ttl: 10.seconds,
          skip_nil: true
        ) { google_directions.body }

        return nil if response_body.blank?
        parse_and_success(response_body)
      rescue => e
        Rails.logger.error("[#{SERVICE_TYPE}] Request failed: #{e.message}")
        failed(" #{e.message}")
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
