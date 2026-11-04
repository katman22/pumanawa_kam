# frozen_string_literal: true

module WeatherMonitoring
  class ClaimAlertAcquisition < ApplicationService
    def initialize(acquisition:, clock: -> { Time.current }, policy: {})
      @state, @clock, @policy = acquisition, clock, policy
    end

    def call
      if WeatherAlertAcquisition.connection_pool.with_connection(&:transaction_open?)
        return failed(code: "acquisition_transaction_open", decision: self.class.scheduling_facts(@state, at: @clock.call.utc)
          .merge(disposition: "failed", reason: "acquisition_transaction_open"))
      end

      result = nil
      @state.with_lock do
        at = @clock.call.utc
        @decision = self.class.scheduling_facts(@state, at: at)
        result = eligibility(at)
        next if result

        if @state.initial_window_start_at.nil? && @state.last_attempt_at &&
            (@state.consecutive_failures.positive? || !@state.last_success_at || @state.last_success_at < @state.last_attempt_at || @state.lease_token.present?)
          # Old attempts have no atomic provenance receipt. Their source rows
          # cannot safely be assigned to this point by time proximity alone.
          result = failed(code: "legacy_unfinished_alert_acquisition", acquisition_id: @state.id,
            decision: @decision.merge(disposition: "invalid", reason: "legacy_unfinished_alert_acquisition"))
          next
        end

        policy = AlertAcquisitionPolicy.call(at: at, watermark: @state.covered_through_at,
          initial_window_start_at: @state.initial_window_start_at, policy: @policy)
        if policy.failure?
          result = failed(policy.value.merge(decision: @decision.merge(disposition: "invalid", reason: policy.value[:code])))
          next
        end
        reclaimed = @state.lease_token.present?
        @decision.merge!(disposition: "claimed", reason: recovery?(policy.value) ? "recovery_due" : "acquisition_due")
        @state.update!(lease_token: SecureRandom.uuid, lease_expires_at: policy.value[:lease_expires_at], last_attempt_at: at,
          initial_window_start_at: @state.initial_window_start_at || policy.value[:from])
        result = successful(disposition: "claimed", acquisition_id: @state.id, decision: @decision, token: @state.lease_token,
          version: @state.lock_version, reclaimed: reclaimed, query: @state.query.deep_dup, pending_evidence: @state.pending_evidence&.deep_dup,
          window: policy.value.slice(:from, :through, :coverage_gap, :coverage_status))
      end
      result
    rescue ActiveRecord::ActiveRecordError => error
      failed(code: "alert_acquisition_persistence_error", error_class: error.class.name,
        decision: @decision&.merge(disposition: "failed", reason: "alert_acquisition_persistence_error"))
    end

    # Safe diagnostics only; eligibility decisions still require the row lock.
    def self.scheduling_facts(state, at:)
      { acquisition_id: state.id, provider: state.provider, scope_key: state.scope_key,
        decision_at: at, next_check_at: state.next_check_at, lease_expires_at: state.lease_expires_at,
        last_attempt_at: state.last_attempt_at, last_success_at: state.last_success_at,
        consecutive_failures: state.consecutive_failures, last_error_code: state.last_error_code,
        covered_through_at: state.covered_through_at, pending_evidence: !state.pending_evidence.nil? }
    end

    private

    def recovery?(window)
      lookback = @policy.fetch(:lookback, AlertAcquisitionPolicy::DEFAULTS.fetch(:lookback))
      !@state.pending_evidence.nil? || @state.lease_token.present? || @state.consecutive_failures.positive? ||
        (@state.initial_window_start_at.present? && @state.last_success_at.nil?) ||
        (@state.covered_through_at && @state.covered_through_at < window.fetch(:through) - lookback)
    end

    def eligibility(at)
      reason = if !@state.enabled?
        "disabled"
      elsif @state.provider != "noaa" || @state.scope_key != WeatherAlertAcquisition::PILOT_SCOPE
        "pilot_scope_only"
      elsif @state.lease_expires_at && @state.lease_expires_at > at
        "leased"
      elsif @state.next_check_at && @state.next_check_at > at
        "not_due"
      end
      return successful(disposition: "skipped", reason: reason, acquisition_id: @state.id,
        decision: @decision.merge(disposition: "skipped", reason: reason)) if reason

      # Authorization for this geographic pilot, not ownership by a Resort.
      # No forecast-monitor enabled state gates source acquisition.
      pilot = Resort.find_by(slug: "brighton")
      expected = pilot && { "type" => "point", "latitude" => pilot.latitude, "longitude" => pilot.longitude }
      failed(code: "unapproved_acquisition_geography", acquisition_id: @state.id,
        decision: @decision.merge(disposition: "invalid", reason: "unapproved_acquisition_geography")) unless expected && @state.query == expected
    end
  end
end
