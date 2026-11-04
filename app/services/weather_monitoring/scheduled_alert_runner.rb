# frozen_string_literal: true

module WeatherMonitoring
  class ScheduledAlertRunner < ApplicationService
    def call
      summary = { configured_count: 0, inspected_count: 0, candidate_count: 0, invoked_count: 0,
        successful_count: 0, skipped_count: 0, failed_count: 0, outcomes: [] }
      states = WeatherAlertAcquisition.order(:id).to_a
      summary[:configured_count] = states.size
      # Preserve candidate_count's original enabled/approved/due query meaning.
      summary[:candidate_count] = WeatherAlertAcquisition.where(enabled: true, provider: "noaa", scope_key: WeatherAlertAcquisition::PILOT_SCOPE)
        .where("next_check_at IS NULL OR next_check_at <= ?", Time.current).count
      states.each do |state|
        result = inspect_scope(state)
        summary[:inspected_count] += 1
        summary[:invoked_count] += 1 if result.value.dig(:decision, :disposition) == "claimed"
        key = result.failure? ? :failed_count : (result.value[:disposition] == "skipped" ? :skipped_count : :successful_count)
        summary[key] += 1
        summary[:outcomes] << result.to_h
      end
      summary[:failed_count].zero? ? successful(summary) : failed(summary)
    rescue StandardError => error
      failed(summary.merge(code: "alert_scheduler_error", error_class: error.class.name))
    end

    private

    def inspect_scope(state)
      facts = ClaimAlertAcquisition.scheduling_facts(state, at: Time.current.utc)
      result = AcquireAlerts.call(acquisition: state)
      ServiceResult.new(success: result.success?, value: result.value.merge(acquisition_id: state.id,
        provider: state.provider, scope_key: state.scope_key,
        decision: result.value[:decision] || facts.merge(disposition: "failed", reason: result.value[:code])))
    rescue StandardError => error
      failed(acquisition_id: state.id, provider: state.provider, scope_key: state.scope_key,
        code: "alert_scope_execution_error", error_class: error.class.name,
        decision: facts&.merge(disposition: "failed", reason: "alert_scope_execution_error"))
    end
  end
end
