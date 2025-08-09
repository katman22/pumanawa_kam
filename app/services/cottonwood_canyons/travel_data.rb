# frozen_string_literal: true

module CottonwoodCanyons
  class TravelData
    attr_reader :resort

    DEFAULT_NO_WARNINGS = "No google traffic warnings."
    WEATHER_ERROR = "No weather data available currently."
    TRAVEL_ERROR = "No travel data available currently."

    def initialize(resort:)
      @origin = resort.departure_point
      @destination = resort.location
      @resort = resort
    end

    def call
      directions_response = Google::Directions.new(origin: @origin, destination: @destination).call
      from_response = Google::Directions.new(origin: @destination, destination: @origin).call
      {
        resort: resort.resort_name,
        to_resort: extract_duration(directions_response),
        from_resort: extract_duration(from_response),
        departure_point: resort.departure_point,
        parking: "Parking Open",
        weather: resort_forecast,
        traffic: extract_warnings(directions_response),
        updated_at: DateTime.current.strftime("%a %l:%M")
      }
    rescue => e
      Rails.logger.error("CanyonTravelTimeService failed: #{e.message}")
      { error: TRAVEL_ERROR }
    end

    private

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

    def resort_forecast
      provider = "openweather"
      forecaster = Weather::DiscussionForecaster.(provider, resort.latitude, resort.longitude, "imperial")
      return WEATHER_ERROR unless forecaster.success?

      forecast = forecaster.value
      "#{forecast[:short_term]}"
    end
  end
end
