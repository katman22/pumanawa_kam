# frozen_string_literal: true

module Udot
  class Cameras < ApplicationService
    attr_reader :resort

    UDOT_KEY   = ENV.fetch("UDOT_KEY", nil)
    UDOT_API   = ENV.fetch("UDOT_API", nil)
    UDOT_ERROR = "No UDOT data available currently."
    CAMERAS    = "cameras"
    CACHE_TTL  = 120 # seconds

    def initialize(resort:)
      @resort = resort
    end

    def call
      # Light cache keyed by resort to smooth spikes
      key = "udot:cameras:#{resort.slug}"
      result = Rails.cache.fetch(key, expires_in: CACHE_TTL, race_condition_ttl: 5) do
        fetch_and_merge_cameras
      end

      return failed(" #{UDOT_ERROR}") if result.nil? || !result.is_a?(Array)
      successful(result)
    rescue => e
      Rails.logger.error("[UDOT Cameras] #{e.class}: #{e.message}")
      failed(" #{UDOT_ERROR}")
    end

    private

    def fetch_and_merge_cameras
      resp = Udot::FetchType.new(type: CAMERAS, filter: filter_for(resort, "camera")).call

      # If the upstream call failed, don’t touch value
      return nil if resp.failure?

      upstream = Array(resp.value)

      # Keep only cameras that aren’t explicitly disabled
      enabled = upstream.select do |cam|
        status = cam.is_a?(Hash) ? dig_sym(cam, "Views", 0, "Status") : nil
        status.to_s.strip.downcase != "disabled"
      end

      # Add resort-curated cameras of kind "traffic" (already normalized JSON in DB)
      curated = Array(resort.cameras.where(kind: "traffic").map(&:data))

      merged = (enabled + curated)

      # Deduplicate by "Id" (stringify to keep stable)
      uniq_by_id = {}
      merged.each do |cam|
        id = cam.is_a?(Hash) ? cam["Id"] || cam[:Id] : nil
        next if id.nil?
        key = id.to_s
        # Prefer curated record if duplicate Id appears
        if uniq_by_id.key?(key)
          uniq_by_id[key] = cam if curated.include?(cam)
        else
          uniq_by_id[key] = cam
        end
      end

      uniq_by_id.values
    end

    def filter_for(resort, kind)
      f = resort.resort_filters.find { |rf| rf.kind == kind }
      f&.parsed_data || {}
    end

    # Safe dig that works for string/ symbol keys without raising
    def dig_sym(h, *path)
      cur = h
      path.each do |k|
        if cur.is_a?(Array)
          cur = cur[k] # numeric index expected
        elsif cur.is_a?(Hash)
          cur = cur[k] || cur[k.to_s] || cur[k.to_s.to_sym]
        else
          return nil
        end
      end
      cur
    end
  end
end
