# app/services/cottonwood_canyons/google/directions.rb
# frozen_string_literal: true

module CottonwoodCanyons
  module Google
    class Directions < ApplicationService
      GOOGLE_DIRECTIONS_URL = "https://maps.googleapis.com/maps/api/directions/json"
      DEPARTURE_TIME = "now"
      TRAFFIC_MODEL  = "best_guess"
      SERVICE_TYPE   = "Google Directions Service"
      CACHE_SECONDS  = 180
      HTTP_TIMEOUT_S = 8

      def initialize(origin:, destination:)
        @origin      = origin
        @destination = destination
      end

      def call
        key = cache_key_for(@origin, @destination)

        if (cached = Rails.cache.read(key))
          Rails.logger.info("[#{SERVICE_TYPE}] Cache hit for #{key}")
          return parse_and_success(cached)
        end

        Rails.logger.info("[#{SERVICE_TYPE}] Cache miss for #{key}, calling Google API…")

        # We cache the raw JSON string. skip_nil ensures empty/failed bodies don’t get cached.
        response_body = Rails.cache.fetch(
          key,
          expires_in: CACHE_SECONDS.seconds,
          race_condition_ttl: 10.seconds,
          skip_nil: true
        ) do
          res = google_directions

          # Guard: HTTP status must be 200
          unless res&.code == 200
            raise "HTTP #{res&.code || 'N/A'} from Google Directions"
          end

          body = res.body
          if body.nil? || body.strip.empty?
            # Don’t cache empties; let caller fall back to stale if any
            nil
          else
            body
          end
        end

        return failed(" empty body from Google") if response_body.nil? || response_body.strip.empty?

        parse_and_success(response_body)
      rescue => e
        Rails.logger.error("[#{SERVICE_TYPE}] Request failed: #{e.class}: #{e.message}")
        failed(" #{e.message}")
      end

      private

      def parse_and_success(response_body)
        parsed = JSON.parse(response_body) rescue nil
        return failed(" invalid JSON from Google") if parsed.nil?

        # Normalize keys once
        parsed = deep_symbolize(parsed)

        # Respect Google payload status
        # https://developers.google.com/maps/documentation/directions/intro#StatusCodes
        status = parsed[:status].to_s
        case status
        when "OK"
          routes = parsed[:routes] || []
          successful(routes)
        when "ZERO_RESULTS"
          successful([])  # treat as success (no route)
        else
          msg = parsed.dig(:error_message) || status
          failed(" Google status #{status}: #{msg}")
        end
      end

      def google_directions
        HTTParty.get(
          GOOGLE_DIRECTIONS_URL,
          query: {
            origin:         @origin,
            destination:    @destination,
            departure_time: DEPARTURE_TIME,
            traffic_model:  TRAFFIC_MODEL,
            key:            ENV["GOOGLE_API_KEY"]
          },
          headers: {
            "Accept"      => "application/json",
            "User-Agent"  => "CanyonTraveller/1.0 (Rails)"
          },
          timeout: HTTP_TIMEOUT_S # caps both open/read in HTTParty
        )
      end

      # === Time-bucketed key: one key per bucket per O/D pair ===
      def cache_key_for(origin, destination)
        bucket = (Time.now.utc.to_i / CACHE_SECONDS) # rotates every 180s
        o = normalize(origin)
        d = normalize(destination)
        # Keep the shape stable so your logs match:
        # [Google Directions Service] Cache hit for google_directions:o:...:d:...:dep:now:tm:best_guess:b:NNN
        %W[google_directions o:#{o} d:#{d} dep:#{DEPARTURE_TIME} tm:#{TRAFFIC_MODEL} b:#{bucket}].join(":")
      end

      def normalize(value)
        value.to_s.strip.downcase.gsub(/\s+/, " ")
      end

      def deep_symbolize(obj)
        case obj
        when Array
          obj.map { |v| deep_symbolize(v) }
        when Hash
          obj.each_with_object({}) do |(k, v), h|
            h[k.to_s.to_sym] = deep_symbolize(v)
          end
        else
          obj
        end
      end
    end
  end
end
