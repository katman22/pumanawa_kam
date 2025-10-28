# app/services/cottonwood_canyons/google/directions_fetcher.rb
module CottonwoodCanyons
  module Google
    class DirectionsFetcher
      DEFAULT_BUCKET_SECONDS = 300
      DEFAULT_EXPIRES        = 6.minutes
      STALE_KEY_PREFIX       = "gdir:last:v2:"

      def self.call(origin:, destination:, bucket_seconds: DEFAULT_BUCKET_SECONDS, expires_in: DEFAULT_EXPIRES)
        new(origin, destination, bucket_seconds, expires_in).call
      end

      def initialize(origin, destination, bucket_seconds, expires_in)
        @origin, @destination = origin, destination
        @bucket_seconds = bucket_seconds
        @expires_in     = expires_in
      end

      def call
        bucket  = (Time.now.to_i / @bucket_seconds).to_i
        key     = cache_key(bucket)
        lastkey = last_good_key

        Rails.cache.fetch(key, expires_in: @expires_in, race_condition_ttl: 10) do
          SINGLE_FLIGHT.do(key) do
            begin
              resp = with_timeouts(8) do
                Google::Directions.new(origin: @origin, destination: @destination).call
              end

              # Treat non-success or blank routes as an error (so we try stale)
              if !resp.respond_to?(:success?) || !resp.success? || resp.value.blank?
                raise "Directions not OK (success?=#{resp.respond_to?(:success?) && resp.success?}, routes=#{resp.respond_to?(:value) ? resp.value&.size : 'n/a'})"
              end

              Rails.cache.write(lastkey, resp, expires_in: 24.hours)
              resp
            rescue => e
              Rails.logger.warn("[DirectionsFetcher] live fetch failed (#{e.class}: #{e.message}); serving stale if present")
              stale = Rails.cache.read(lastkey)
              raise e if stale.nil?
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

      def with_timeouts(seconds)
        Timeout.timeout(seconds) { yield }
      end
    end
  end
end
