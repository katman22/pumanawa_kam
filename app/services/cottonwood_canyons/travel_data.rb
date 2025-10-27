# frozen_string_literal: true

module CottonwoodCanyons
  class TravelData
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
      directions_response = Google::Directions.new(origin: @origin, destination: @destination).call if get_to?
      from_response = Google::Directions.new(origin: @destination, destination: @origin).call if get_from?
      {
        resort: resort.resort_name,
        to_resort:  get_to? ? extract_duration(directions_response) : "N/A",
        from_resort:  get_from? ? extract_duration(from_response): "N/A",
        departure_point: resort.departure_point,
        parking: parking_data,
        weather: resort_forecast,
        traffic: extract_warnings(directions_response),
        updated_at: DateTime.current.strftime("%a %l:%M")
      }
    rescue => e
      Rails.logger.error("CanyonTravelTimeService failed: #{e.message}")
      { error: TRAVEL_ERROR }
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
      return [] unless response.success? && response.value.present?
      route = response.value.first
      return [] if route.nil? || route[:warnings].nil?
      route[:warnings] || []
    end

    def extract_duration(response)
      return "N/A" unless response.success? && response.value.present?
      leg = response.value.first["legs"].first.symbolize_keys
      leg[:duration_in_traffic].symbolize_keys!
      return leg[:duration_in_traffic][:text].gsub!("mins", "").strip! if leg && leg[:duration_in_traffic]

      leg[:duration][:text] rescue TRAVEL_ERROR
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
