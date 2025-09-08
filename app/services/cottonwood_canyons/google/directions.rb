# app/services/cottonwood_canyons/google/directions.rb
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
        key = cache_key_for(@origin, @destination)
        if (cached = Rails.cache.read(key))
          Rails.logger.info("[#{SERVICE_TYPE}] Cache hit for #{key}")
          return parse_and_success(cached)
        end

        Rails.logger.info("[#{SERVICE_TYPE}] Cache miss for #{key}, calling Google API…")
        response_body = Rails.cache.fetch(
          key,
          expires_in: 70.seconds,
          race_condition_ttl: 10.seconds,
          skip_nil: true
        ) do
          google_directions.body
        end

        return nil if response_body.blank?
        parse_and_success(response_body)
      rescue => e
        Rails.logger.error("[#{SERVICE_TYPE}] Request failed: #{e.message}")
        failed(FAILED_MESSAGE.call(e.message))
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
          key: ENV["GOOGLE_API_KEY"]
        })
      end

      # === Time-bucketed key: one cache key per minute per O/D pair ===
      def cache_key_for(origin, destination)
        bucket = Time.now.utc.to_i / 60 # changes once per minute (UTC for consistency)
        o = origin.to_s.strip
        d = destination.to_s.strip
        "google_directions:#{o}:#{d}:#{bucket}"
      end
    end
  end
end
