# frozen_string_literal: true

module WeatherMonitoring
  # Finite manual acquisition only. No forecast state or scheduling is changed.
  class DetectAlertSignals < ApplicationService
    def initialize(resort:, detected_at: Time.current)
      @resort, @at = resort, detected_at
    end

    def call
      return failed(code: "pilot_resorts_only") unless @resort&.persisted? && EvaluateResort::ALLOWED_RESORT_TYPES.include?(@resort.slug)
      return failed(code: "monitor_disabled") unless ResortWeatherMonitor.exists?(resort_id: @resort.id, enabled: true, provider: "noaa")

      # Active-only responses cannot reliably expose explicit cancellations or
      # expired messages. A bounded recent-history query retains those messages.
      fetched = Noaa::Alerts::Fetch.call(latitude: @resort.latitude, longitude: @resort.longitude, active: false, since: @at - 24.hours)
      return fetched if fetched.failure?

      ProcessAlertCollection.call(collection: fetched.value, detected_at: @at, since: @at - 24.hours, resorts: [ @resort ],
        query: { "type" => "point", "latitude" => @resort.latitude, "longitude" => @resort.longitude })
    end
  end
end
