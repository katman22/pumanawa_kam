# app/services/cottonwood_canyons/google/directions_fetcher.rb
# frozen_string_literal: true

module CottonwoodCanyons
  module Google
    class DirectionsFetcher
      DEFAULT_EXPIRES        = 6.minutes
      STALE_KEY_PREFIX       = "gdir:last:v3:"   # bump prefix since key format changed
      SERVICE_TYPE           = "DirectionsFetcher"

      def self.call(origin:, destination:, expires_in: DEFAULT_EXPIRES)
        new(origin, destination, expires_in).call
      end

      def initialize(origin, destination, expires_in)
        @origin, @destination = origin, destination
        @expires_in           = expires_in
      end

      def call
        key     = stable_key(@origin, @destination)       
        lastkey = last_good_key(@origin, @destination)

        Rails.cache.fetch(key, expires_in: @expires_in, race_condition_ttl: 10.seconds, skip_nil: true) do
          SINGLE_FLIGHT.do(key) do
            begin
              resp = with_timeouts(8) do
                Google::Directions.new(origin: @origin, destination: @destination).call
              end

              unless resp.respond_to?(:success?) && resp.success? && resp.value.present?
                raise "Directions not OK (success?=#{resp.respond_to?(:success?) && resp.success?}, routes=#{resp.respond_to?(:value) ? resp.value&.size : 'n/a'})"
              end

              # keep a last-known-good in case the next live fetch dies
              Rails.cache.write(lastkey, resp, expires_in: 24.hours)
              resp
            rescue => e
              Rails.logger.warn("[#{SERVICE_TYPE}] live fetch failed (#{e.class}: #{e.message}); serving stale if present")
              stale = Rails.cache.read(lastkey)
              raise e if stale.nil?
              stale
            end
          end
        end
      end

      private

      # === Stable key: origin + destination only ===
      def stable_key(origin, destination)
        "gdir:v3:#{normalize(origin)}|#{normalize(destination)}"
      end

      def last_good_key(origin, destination)
        "#{STALE_KEY_PREFIX}#{normalize(origin)}|#{normalize(destination)}"
      end

      def normalize(value)
        value.to_s.strip.downcase.gsub(/\s+/, " ")
      end

      def with_timeouts(seconds)
        Timeout.timeout(seconds) { yield }
      end
    end
  end
end
