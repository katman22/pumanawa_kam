# frozen_string_literal: true

module CottonwoodCanyons
  class TravelTimes
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
        updated_at: DateTime.current.strftime("%a %l:%M")
      }
    rescue => e
      Rails.logger.error("CanyonTravelTimeService failed: #{e.message}")
      { error: TRAVEL_ERROR }
    end

    private

    def extract_duration(response)
      return "N/A" unless response.success? && response.value.present?
      leg = response.value.first["legs"].first.symbolize_keys
      leg[:duration_in_traffic].symbolize_keys!
      return leg[:duration_in_traffic][:text].gsub!("mins", "").strip! if leg && leg[:duration_in_traffic]

      leg[:duration][:text] rescue TRAVEL_ERROR
    end
  end
end
