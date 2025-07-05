module CottonwoodCanyons
  class TravelData
    attr_reader :resort

    DEFAULT_NO_WARNINGS = "No google traffic warnings."

    def initialize(resort:)
      @origin = resort.departure_point
      @destination = resort.location
      @resort = resort
    end

    def call
      directions_response = Google::Directions.new(origin: @origin, destination: @destination).call
      warnings = extract_warnings(directions_response)
      to_resort_time = extract_duration(directions_response)
      from_response = Google::Directions.new(origin: @destination, destination: @origin).call
      from_resort_time = extract_duration(from_response)
      {
        resort: resort.resort_name,
        to_resort: to_resort_time,
        from_resort: from_resort_time,
        departure_point: resort.departure_point,
        parking: "Parking Open",
        weather: "Sunny, clear high of 32",
        traffic: warnings.join(", "),
        updated_at: DateTime.current.strftime("%a %l:%M") }
    rescue => e
      Rails.logger.error("CanyonTravelTimeService failed: #{e.message}")
      { error: "Could not fetch travel time" }
    end

    private

    def extract_warnings(response)
      return [] unless response.success? && response.value.present?
      route = response.value.first
      return [ DEFAULT_NO_WARNINGS ] if route.nil? || route[:warnings].nil?
      route[:warnings] || []
    end

    def extract_duration(response)
      return "N/A" unless response.success? && response.value.present?
      leg = response.value.first["legs"].first.symbolize_keys
      leg[:duration_in_traffic].symbolize_keys!
      return leg[:duration_in_traffic][:text].gsub!("mins", "").strip! if leg && leg[:duration_in_traffic]

      leg[:duration][:text] rescue "Unknown"
    end
  end
end
