# app/services/cottonwood_canyons/google/directions_fetcher.rb
module CottonwoodCanyons
  module Google
    class DirectionsFetcher
      DEFAULT_EXPIRES        = 6.minutes
      STALE_KEY_PREFIX       = "gdir:last:v2:"  # keep if you like the stale fallback

      def self.call(origin:, destination:, expires_in: DEFAULT_EXPIRES)
        new(origin, destination, expires_in).call
      end

      def initialize(origin, destination, expires_in)
        @origin, @destination = origin, destination
        @expires_in           = expires_in
      end

      def call
        key     = DirectionsKey.key_for(@origin, @destination) # unified key!
        lastkey = last_good_key

        Rails.cache.fetch(key, expires_in: @expires_in, race_condition_ttl: 10) do
          SINGLE_FLIGHT.do(key) do
            begin
              resp = with_timeouts(8) do
                Google::Directions.new(origin: @origin, destination: @destination).call
              end

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

      def last_good_key
        # unify this with the same normalization to avoid drift
        norm = DirectionsKey.key_for(@origin, @destination)
        "#{STALE_KEY_PREFIX}#{norm}"
      end

      def with_timeouts(seconds) = Timeout.timeout(seconds) { yield }
    end
  end
end
