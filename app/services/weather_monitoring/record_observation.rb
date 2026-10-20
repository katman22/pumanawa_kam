# frozen_string_literal: true

module WeatherMonitoring
  class RecordObservation < ApplicationService
    def initialize(resort:, normalized:, snapshot:, fetched_at:, source_metadata: {})
      @resort, @normalized, @snapshot, @at, @metadata = resort, normalized, snapshot, fetched_at, source_metadata
    end

    def call
      attributes = @normalized.slice("source_key", "source_updated_at", "content_sha256", "normalization_version", "selected_intervals")
        .merge("resort_id" => @resort.id, "provider" => "noaa", "first_fetched_at" => @at,
          "forecast_window_start" => @snapshot["summary"]["window_start"], "forecast_window_end" => @snapshot["summary"]["window_end"],
          "summary" => @snapshot["summary"], "quality" => @snapshot["quality"],
          "source_metadata" => @normalized.fetch("source_metadata").merge(@metadata))
      identity = attributes.slice("resort_id", "provider", "source_key", "source_updated_at", "content_sha256", "normalization_version")
      existing = WeatherForecastObservation.find_by(identity)
      return successful(observation: existing, disposition: "existing") if existing

      observation = WeatherForecastObservation.create_or_find_by!(identity) do |record|
        record.assign_attributes(attributes.except(*identity.keys))
      end
      successful(observation: observation, disposition: observation.previously_new_record? ? "created" : "existing")
    rescue ActiveRecord::RecordInvalid => error
      failed(code: "observation_invalid", details: error.record.errors.full_messages)
    end
  end
end
