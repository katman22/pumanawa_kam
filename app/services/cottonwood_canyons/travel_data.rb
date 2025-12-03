# frozen_string_literal: true

module CottonwoodCanyons
  class TravelData < CottonwoodCanyons::TravelBase
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
      # one or both calls depending on @type
      to_resp   = get_to?   ? Google::DirectionsFetcher.call(origin: @origin, destination: @destination, expires_in: dynamic_ttl) : nil
      from_resp = get_from? ? Google::DirectionsFetcher.call(origin: @destination, destination: @origin, expires_in: dynamic_ttl) : nil

      result = {
        resort: resort.resort_name,
        to_resort:   get_to?   ? extract_duration(to_resp)   : "N/A",
        from_resort: get_from? ? extract_duration(from_resp) : "N/A",
        departure_point: resort.departure_point,
        parking: parking_data,
        weather: resort_forecast,
        traffic: extract_warnings(to_resp),
        overview_polyline: extract_polyline(to_resp), # ← add polyline (from the “to” route)
        updated_at: DateTime.current.strftime("%a %l:%M")
      }
      successful(result)
    rescue => e
      Rails.logger.error("CanyonTravelTimeService failed: #{e.message}")
      failed(e.message)
    end

    private

    def get_from?
      %w[all from].include?(@type)
    end

    def get_to?
      %w[all to].include?(@type)
    end

    def extract_warnings(response)
      udot_information || google_warnings(response)
    end

    def google_warnings(response)
      return [] unless response&.success? && response.value.present?
      route = response.value.first
      route && route["warnings"] || route && route[:warnings] || []
    end

    def udot_information
      udot_response = Udot::Warnings.new(resort: resort).call
      return UDOT_ERROR if udot_response.failure?

      udot_response.value[:summary]
    end

    def parking_data
      {
        operations: operation_hours
      }
    end

    def operation_hours
      parking_profile = resort.parking_profiles.where(live: true).first
      return { operating_days: [], holiday_open_days: [] } if parking_profile.nil?

      parking_profile.operations
    end

    def resort_forecast
      provider = "noaa"
      forecaster = Weather::DiscussionForecaster.(provider, resort.latitude, resort.longitude, "imperial")
      hourly_forecaster = Weather::HourlyForecaster.(provider, resort.latitude, resort.longitude)
      return WEATHER_ERROR unless forecaster.success?

      forecast = forecaster.value
      hourly_forecast = hourly_forecaster.value
      { summary: "#{forecast[:short_term]}", hourly: hourly_forecast["periods"][..6] }
    end
  end
end
