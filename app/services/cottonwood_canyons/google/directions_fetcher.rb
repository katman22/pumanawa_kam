# app/services/cottonwood_canyons/google/directions_fetcher.rb
# frozen_string_literal: true

module CottonwoodCanyons
  module Google
    class DirectionsFetcher
      # One place to tweak bucket sizing + TTL:
      DEFAULT_BUCKET_SECONDS = 300 # 5 min
      DEFAULT_EXPIRES        = 6.minutes
      STALE_KEY_PREFIX       = "gdir:last:v2:"

      def self.call(origin:, destination:, bucket_seconds: DEFAULT_BUCKET_SECONDS, expires_in: DEFAULT_EXPIRES)
        new(origin, destination, bucket_seconds, expires_in).call
      end

      def initialize(origin, destination, bucket_seconds, expires_in)
        @origin, @destination = origin, destination
        @bucket_seconds = bucket_seconds
        @expires_in = expires_in
      end

      def call
        bucket = (Time.now.to_i / @bucket_seconds).to_i
        key    = cache_key(bucket)
        last_key = last_good_key

        Rails.cache.fetch(key, expires_in: @expires_in, race_condition_ttl: 10) do
          # Only ONE miss executes this block:
          SINGLE_FLIGHT.do(key) do
            # Try live Google with an 8s cap
            begin
              resp = with_timeouts(8) do
                Google::Directions.new(origin: @origin, destination: @destination).call
              end

              # Persist a last-good snapshot too (for stale-on-error)
              Rails.cache.write(last_key, resp, expires_in: 24.hours)
              resp
            rescue => e
              Rails.logger.warn("[DirectionsFetcher] live fetch failed (#{e.class}: #{e.message}); serving stale if present")
              stale = Rails.cache.read(last_key)
              raise e if stale.nil? # nothing to serve
              stale
            end
          end
        end
      end

      private

      def cache_key(bucket)
        "gdir:v2:#{@origin}|#{@destination}|#{bucket}"
      end

      def last_good_key
        "#{STALE_KEY_PREFIX}#{@origin}|#{@destination}"
      end

      # If your Google::Directions already sets low timeouts, you can skip this.
      def with_timeouts(seconds)
        Timeout.timeout(seconds) { yield }
      end
    end
  end
end
