# frozen_string_literal: true

module CottonwoodCanyons
  module Google
    class DirectionsFetcher
      def self.call(origin:, destination:, bucket_seconds: 300, expires_in: 6.minutes)
        bucket = Time.now.to_i / bucket_seconds
        key = "gdir:v2:#{origin}|#{destination}|#{bucket}"

        Rails.cache.fetch(key, expires_in: expires_in) do
          Google::Directions.new(origin: origin, destination: destination).call
        end
      end
    end
  end
end
