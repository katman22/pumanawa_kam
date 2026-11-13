# frozen_string_literal: true

module WeatherMonitoring
  class CompleteAlertAcquisition < ApplicationService
    def initialize(acquisition:, claim:, result:, clock: -> { Time.current }, policy: {})
      @state, @claim, @result, @clock, @policy = acquisition, claim, result, clock, policy
    end

    def call
      outcome = nil
      @state.reload.with_lock(requires_new: true) do
        at = @clock.call.utc
        unless @state.owns_claim?(@claim, at: at) && @state.pending_evidence == @claim[:pending_evidence]
          outcome = failed(code: "alert_acquisition_superseded", acquisition_id: @state.id)
          next
        end
        failures = @result.success? ? 0 : @state.consecutive_failures + 1
        policy = AlertAcquisitionPolicy.call(at: at, failures: failures, provider_retry_at: @result.value[:retry_at], policy: @policy)
        if policy.failure?
          outcome = policy
          next
        end
        window = @claim.fetch(:window)
        skips = Array(@result.value[:outcomes]).select { |row| row[:disposition] == "skipped" }.map { |row| row[:reason] }.tally
        summary = { "coverage_status" => window[:coverage_status], "window_start" => window[:from].iso8601,
          "window_end" => window[:through].iso8601, "success" => @result.success?,
          "coverage_gap" => window[:coverage_gap], "window_processed" => @result.success?,
          "created_count" => @result.value[:created_count], "code" => @result.value[:code], "error_class" => @result.value[:error_class],
          "reclaimed_lease" => @claim[:reclaimed] }
        summary.merge!("observation_count" => @result.value[:observation_count], "signal_skip_reasons" => skips)
        summary.merge!("replayed_observation_count" => @result.value[:replayed_observation_count], "replayed_created_count" => @result.value[:replayed_created_count])
        attributes = { lease_token: nil, lease_expires_at: nil, consecutive_failures: failures, last_result: summary }
        if @result.success?
          gaps = @state.coverage_gaps | Array.wrap(window[:coverage_gap])
          attributes.merge!(last_success_at: at, covered_from_at: window[:from], covered_through_at: window[:through],
            coverage_gaps: gaps, next_check_at: policy.value[:next_check_at], last_error_code: nil, pending_evidence: nil)
        else
          attributes.merge!(last_error_code: @result.value[:code] || "alert_acquisition_failed", next_check_at: policy.value[:retry_at])
        end
        @state.update!(**attributes)
        value = { acquisition_id: @state.id, scope_key: @state.scope_key, disposition: @result.success? ? "successful" : "failed",
          code: @state.last_error_code, error_class: @result.value[:error_class], next_check_at: @state.next_check_at, covered_through_at: @state.covered_through_at,
          coverage_status: window[:coverage_status], coverage_gap: window[:coverage_gap],
          coverage_uncertain: @result.failure? || @state.coverage_gaps.any? || window[:coverage_gap].present?,
          reclaimed_lease: @claim[:reclaimed], created_count: @result.value[:created_count],
          observation_count: @result.value[:observation_count], signal_skip_reasons: skips }
        outcome = @result.success? ? successful(value) : failed(value)
      end
      outcome
    rescue ActiveRecord::ActiveRecordError => error
      failed(code: "alert_acquisition_persistence_error", error_class: error.class.name)
    end
  end
end
