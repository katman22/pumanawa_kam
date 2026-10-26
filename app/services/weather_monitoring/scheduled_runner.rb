# frozen_string_literal: true

module WeatherMonitoring
  class ScheduledRunner < ApplicationService
    SKIP_CODES = %w[evaluation_busy monitor_disabled monitor_missing resort_missing pilot_resorts_only unsupported_provider not_due rate_limited superseded_evaluation].freeze

    def initialize(run_id: SecureRandom.uuid)
      @summary = { run_id: run_id, started_at: nil, completed_at: nil, candidate_count: 0,
        invoked_count: 0, skipped_count: 0, successful_count: 0, failed_count: 0, degraded_count: 0,
        outcomes: [], errors: [] }
    end

    def call
      @summary[:started_at] = Time.current.utc
      monitors = candidates.to_a
      @summary[:candidate_count] = monitors.size
      monitors.each { |monitor| process(monitor) }
      complete
    rescue StandardError => error
      @summary[:errors] << { code: "scheduler_error", error_class: error.class.name }
      complete
    end

    private

    def candidates
      ResortWeatherMonitor.joins(:resort).includes(:resort)
        .where(enabled: true, provider: "noaa", resorts: { slug: EvaluateResort::ALLOWED_RESORT_TYPES })
        .where("next_check_at IS NULL OR next_check_at <= :now OR next_probe_at IS NULL OR next_probe_at <= :now", now: @summary[:started_at])
        .order(:id)
    end

    def process(monitor)
      result = RunEvaluation.call(resort: monitor.resort, scheduled: true)
      value = result.value
      execution = value.fetch(:execution)
      outcome = { monitor_id: monitor.id, resort_id: monitor.resort_id, resort: monitor.resort.slug,
        invoked: execution[:invoked], mode: execution[:mode], evaluation_at: execution[:evaluation_at] }
      @summary[:invoked_count] += 1 if outcome[:invoked]
      if !outcome[:invoked] && SKIP_CODES.include?(value[:code])
        outcome.merge!(status: "skipped", reason: value[:code], retry_at: value[:retry_at])
        @summary[:skipped_count] += 1
      elsif result.failure?
        outcome.merge!(status: "failed", reason: value[:code], error_class: value[:error_class])
        @summary[:failed_count] += 1
      else
        quality = value.dig(:snapshot, "quality", "state")
        alerts = value.dig(:alerts, :state)
        degraded = quality != "complete" || alerts == "degraded"
        outcome.merge!(status: "successful", degraded: degraded, quality: quality, alert_state: alerts,
          source_updated_at: value[:source_updated_at], observation: value[:observation],
          next_check_at: value.dig(:cadence, "next_check_at"), next_probe_at: value.dig(:cadence, "next_probe_at"))
        @summary[:successful_count] += 1
        @summary[:degraded_count] += 1 if degraded
      end
      @summary[:outcomes] << outcome
    rescue StandardError => error
      @summary[:failed_count] += 1
      @summary[:outcomes] << { monitor_id: monitor.id, resort_id: monitor.resort_id,
        status: "failed", mode: nil, invoked: false, reason: "runner_error", error_class: error.class.name }
    end

    def complete
      @summary[:completed_at] = Time.current.utc
      @summary[:failed_count].zero? && @summary[:errors].empty? ? successful(@summary) : failed(@summary)
    end
  end
end
