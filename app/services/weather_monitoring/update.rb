module WeatherMonitoring
  class Update < ApplicationService
    attr_reader :monitor, :normalized, :at, :cadence, :alerts, :monitor_attributes, :observations, :version

    def initialize(monitor:, normalized:, at:, cadence:, alerts:, monitor_attributes:, observations:, version:)
      @monitor, @normalized  = monitor, normalized
      @version = version
      @at= at
      @cadence, @alerts = cadence, alerts
      @monitor_attributes = monitor_attributes
      @observations = observations
    end

    def call
      outcome = nil
      monitor.with_lock(requires_new: true) do
        unless current_run?
          outcome = failed(code: "superseded_evaluation")
          next
        end
        if monitor.last_source_updated_at && Time.iso8601(normalized["source_updated_at"]) < monitor.last_source_updated_at
          outcome = failed(code: "older_source_revision")
          next
        end

        recorded = RecordObservation.call(**observations)
        if recorded.failure?
          outcome = recorded
          # A failed child result must not commit any writes it made. The
          # savepoint also isolates this rollback from a caller's transaction.
          raise ActiveRecord::Rollback
        end

        assign_cadence
        assign_attributes(recorded)
        assign_alert_state
        monitor.save!
        outcome = successful(observation_disposition: recorded.value[:disposition])
      end
      outcome
    rescue ActiveRecord::ActiveRecordError => e
      failed(code: "persistence_error", error_class: e.class.name)
    rescue StandardError => e
      Rails.error.report(e, handled: true)
      failed(code: "unexpected_error", error_class: e.class.name)
    end

    def assign_alert_state
      return unless alerts&.success? && !alerts.value[:skipped]

      monitor.active_alert_identifiers = alerts.value[:active_identifiers]
      monitor.last_alert_checked_at = at
      monitor.last_decision = monitor.last_decision.merge("processed_alert_revisions" => alerts.value.fetch(:revisions, []))
    end

    # HTTP is finished before this short row lock. Optimistic version + source
    # checks reject slower runs, including concurrent enable/disable operations.
    def current_run?
      monitor.enabled? && monitor.lock_version == version && (!monitor.last_checked_at || monitor.last_checked_at <= at)
    end

    def assign_cadence
      monitor.assign_attributes(cadence.except("reasons"))
    end

    def assign_attributes(recorded)
      prior_alert_revisions = monitor.last_decision.slice("processed_alert_revisions")
      monitor.assign_attributes(monitor_attributes.merge(current_forecast_observation: recorded.value[:observation]))
      monitor.last_decision = monitor.last_decision.merge(prior_alert_revisions)
    end
  end
end
