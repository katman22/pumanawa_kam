# frozen_string_literal: true

module WeatherMonitoring
  # Projection of immutable evidence, never an evaluation or a rolling forecast.
  class MobileSummary < ApplicationService
    SOURCE_STALE_AFTER = 24.hours
    COLUMNS = %i[id resort_id first_fetched_at source_updated_at forecast_window_start forecast_window_end summary quality].freeze

    def initialize(resort:, at: Time.current)
      @resort, @at = resort, at.utc
    end

    def call
      monitor = ResortWeatherMonitor.find_by(resort_id: @resort.id)
      result = { schema_version: 1, generated_at: @at.iso8601,
        resort: { id: @resort.id, slug: @resort.slug, name: @resort.resort_name },
        availability: { state: "unavailable", reason: nil }, forecast: nil,
        monitoring: { last_successful_evaluation_at: monitor&.last_success_at&.iso8601,
          last_evaluation_quality: monitor&.last_decision&.fetch("quality", nil) } }
      reason = unavailable_reason(monitor)
      unless reason
        observation = WeatherForecastObservation.select(*COLUMNS)
          .find_by(id: monitor.current_forecast_observation_id, resort_id: @resort.id)
        reason = "no_snapshot" unless observation
      end
      if reason
        result[:availability][:reason] = reason
      else
        result[:availability][:state] = "available"
        result[:forecast] = forecast(observation)
      end
      successful(result)
    rescue ActiveRecord::ActiveRecordError
      failed(code: "monitor_summary_unavailable")
    end

    private

    def unavailable_reason(monitor)
      return "pilot_only" unless EvaluateResort::ALLOWED_RESORT_TYPES.include?(@resort.slug)
      return "monitor_missing" unless monitor
      return "monitor_disabled" unless monitor.enabled?
      return "unsupported_provider" unless monitor.provider == "noaa"
      return "no_snapshot" unless monitor.current_forecast_observation_id

      nil
    end

    def amount(value)
      row = value.is_a?(Hash) ? value : {}
      { start_at: row["start_at"], end_at: row["end_at"], state: row["state"] || "unknown",
        amount_mm: row["amount_mm"], lower_mm: row["lower_mm"], upper_mm: row["upper_mm"], coverage_seconds: row["coverage_seconds"] }
    end

    def forecast(observation)
      summary, quality = observation.summary, observation.quality
      snow_quality = quality.dig("layers", "snowfallAmount") || {}
      age = (@at - observation.source_updated_at).round
      freshness = age < -5.minutes ? "future_source" : (age > SOURCE_STALE_AFTER ? "stale" : "fresh")
      { observation_id: observation.id, recorded_at: observation.first_fetched_at.iso8601,
        source_updated_at: observation.source_updated_at.iso8601, evaluation_at: summary["evaluation_at"],
        window: { start_at: observation.forecast_window_start.iso8601, end_at: observation.forecast_window_end.iso8601 },
        snowfall: { unit: "mm", total: amount(summary["snowfall"]),
          buckets: Array(summary["buckets"]).map { |row| amount(row).merge(hours: row["hours"]) } },
        first_accumulating_snow: summary["first_accumulating_snow"]&.slice("start_at", "end_at"),
        quality: { state: quality["state"] || "unknown", freshness_at_recording: quality["freshness"],
          snowfall_coverage_seconds: snow_quality["coverage_seconds"],
          gaps: Array(snow_quality["gaps"]).map { |gap| gap.slice("start_at", "end_at") } },
        freshness: { state: freshness, source_age_seconds: age, window_expired: observation.forecast_window_end <= @at } }
    end
  end
end
