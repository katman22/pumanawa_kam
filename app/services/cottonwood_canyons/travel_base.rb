# frozen_string_literal: true

module CottonwoodCanyons
  class TravelBase < ApplicationService
    attr_reader :resort

    DEFAULT_NO_WARNINGS = "No google traffic warnings."
    WEATHER_ERROR = "No weather data available currently."
    TRAVEL_ERROR = "No travel data available currently."

    def initialize(resort:, type: "all")
      @origin = resort.departure_point
      @destination = resort.location
      @resort = resort
      @type = type
    end

    def call
      # Implement in children
    end

    private

    def dynamic_ttl
      hour = Time.current.hour

      case hour
      when 0..3
        30.minutes
      when 4..8
        6.minutes
      when 9..14
        8.minutes
      when 15..19
        6.minutes
      else
        15.minutes
      end
    end

    def extract_duration(response)
      return "N/A" unless response&.success? && response.value.present?

      route = response.value.first
      legs  = route && (route["legs"] || route[:legs])
      leg   = legs&.first
      return "N/A" unless leg

      leg = leg.symbolize_keys
      if leg[:duration_in_traffic]
        dit = leg[:duration_in_traffic].symbolize_keys
        return dit[:text].to_s.gsub("mins", "").strip
      end

      leg.dig(:duration, :text) || TRAVEL_ERROR
    end

    def extract_polyline(response)
      return nil unless response&.success? && response.value.present?
      route = response.value.first
      poly  = route && (route["overview_polyline"] || route[:overview_polyline])
      poly && (poly["points"] || poly[:points])
    end
  end
end
