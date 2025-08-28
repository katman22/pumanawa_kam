# frozen_string_literal: true

module Udot
  class Warnings < ApplicationService
    attr_reader :resort

    UDOT_KEY = ENV.fetch("UDOT_KEY")
    UDOT_API = ENV.fetch("UDOT_API")
    UDOT_ERROR = "No UDOT data available currently."
    ROAD_CONDITIONS = "roadconditions"
    EVENT = "event"
    EXCLUSIONS = "EncodedPolyline"
    ALERTS = "alerts"

    def initialize(resort:)
      @resort = resort
    end

    def call
      events = udot_events
      alerts = udot_alerts
      data = { conditions: udot_conditions, events: events, alerts: alerts, summary: build_traffic_summary(events: events, alerts: alerts) }

      successful(data)
    end

    private

    def build_traffic_summary(events:, alerts:)
      return "Road alert in effect." if alerts.any?

      highlight_event = events.find do |e|
        e[:IsFullClosure] || e[:EventCategory] == "Closure"
      end || events.find { |e| e[:EventCategory] == "Construction" }

      if highlight_event
        location = highlight_event[:Location] || highlight_event[:RoadwayName]
        desc = highlight_event[:Description]&.split("\n")&.first || "Construction in progress."
        return "#{highlight_event[:EventCategory]} on #{location} — #{desc}"
      end

      "No active road events or closures."
    end

    def udot_conditions
      udot_response = Udot::FetchType.new(type: ROAD_CONDITIONS, filter: filter(resort, "roadway")).call
      return UDOT_ERROR if udot_response.failure?
      udot_response.value.map { |entry| entry.except(EXCLUSIONS) }
    end

    def udot_alerts
      udot_response = Udot::FetchType.new(type: ALERTS, filter: filter(resort, "alerts")).call
      return UDOT_ERROR if udot_response.failure?
      udot_response.value
    end

    def udot_events
      udot_response = Udot::FetchType.new(type: EVENT, filter: filter(resort, "event")).call
      return UDOT_ERROR if udot_response.failure?
      udot_response.value.map { |entry|
        {
          "RoadwayName": entry["RoadwayName"],
          "Organization": entry["Organization"],
          "Description": entry["Description"],
          "Comment": entry["Comment"],
          "IsFullClosure": entry["IsFullClosure"],
          "EventCategory": entry["EventCategory"],
          "Location": entry["Location"],
          "MPStart": entry["MPStart"],
          "MPEnd": entry["MPEnd"]
        }
      }
    end

    def filter(resort, kind)
      filter = resort.resort_filters.select { |filter| filter.kind == kind }.first
      filter.parsed_data
    end
  end
end
