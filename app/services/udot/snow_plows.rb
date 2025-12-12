# app/services/udot/snow_plows.rb
module Udot
  class SnowPlows < ApplicationService
    CACHE_TTL = 60.seconds

    attr_reader :resort

    def initialize(resort:)
      @resort = resort
    end

    def call
      key = "udot:snow_plows:#{resort.slug}"
      data = Rails.cache.fetch(key, expires_in: CACHE_TTL, race_condition_ttl: 5) do
        fetch_plows
      end
      return successful([]) if data.blank?

      successful("snow_plows": data)
    rescue => e
      Rails.logger.error("[UDOT SnowPlows] #{e.class}: #{e.message}")
      successful([]) # plows are optional, never break alerts
    end

    private

    def fetch_plows
      resp = Udot::FetchType.new(type: "servicevehicles").call
      return [] if resp.failure?

      plows = normalize(resp.value)
      filter_for_resort(plows)
    end

    def normalize(upstream)
      Array(upstream).map do |plow|
        {
          id: plow["Id"],
          type: "snow_plow",
          name: plow["Name"],
          owner: plow["Owner"],
          bearing: plow["Bearing"].to_i,
          latitude: plow["Latitude"],
          longitude: plow["Longitude"],
          polyline: plow["EncodedPolyline"],
          updated_at: plow["LastUpdated"]
        }
      end
    end

    def filter_for_resort(plows)
      bounds = Resort::RESORT_CORRIDORS[resort.slug.to_sym]&.dig(:bounds)
      return plows if bounds.nil?

      plows.select do |p|
        p[:latitude].between?(bounds[:min_lat], bounds[:max_lat]) &&
          p[:longitude].between?(bounds[:min_lng], bounds[:max_lng])
      end
    end

  end
end
