# frozen_string_literal: true

module WeatherMonitoring
  # Operational entry point shared by manual and scheduled runs. Session
  # locks require a direct/session-compatible PostgreSQL connection, not
  # transaction-mode pooling. No transaction is held during provider requests.
  class RunEvaluation < ApplicationService
    def initialize(resort:, scheduled: false, **options)
      @resort_input, @options, @scheduled = resort, options, scheduled
      @execution = { invoked: false, mode: nil, evaluation_at: nil }
    end

    def call
      resort = @resort_input.is_a?(Resort) ? @resort_input : Resort.find_by(id: @resort_input)
      return execution_result(failed(code: EvaluateResort::RESORT_MISSING)) unless resort&.persisted?
      return execution_result(failed(code: EvaluateResort::RESORT_NOT_ALLOWED)) unless EvaluateResort::ALLOWED_RESORT_TYPES.include?(resort.slug)

      ResortWeatherMonitor.connection_pool.with_connection do |connection|
        # Session advisory locks survive transaction rollback. Refuse enclosing
        # transactions so callers cannot accidentally hold one across HTTP.
        return execution_result(failed(code: "evaluation_transaction_open")) if connection.transaction_open?

        # A stable, positive 60-bit key, shared across Ruby processes. Do not use
        # Ruby's process-randomized String#hash for a database lock identity.
        key = Digest::SHA256.hexdigest("weather_monitoring:resort:#{resort.id}").first(15).to_i(16)
        # These SELECTs have side effects and must never use Rails' query cache.
        acquired = connection.uncached { connection.select_value("SELECT pg_try_advisory_lock(#{key})") }
        return execution_result(failed(code: "evaluation_busy")) unless acquired

        begin
          result = @scheduled ? evaluate_due(resort, connection) : EvaluateResort.call(resort: resort, **@options)
          execution_result(result)
        ensure
          begin
            connection.uncached { connection.select_value("SELECT pg_advisory_unlock(#{key})") }
          rescue StandardError
            # Never return a possibly still-locked session to the pool if
            # explicit unlock failed. Closing it releases session-owned locks.
            connection.disconnect!
            raise
          end
        end
      end
    rescue ActiveRecord::ActiveRecordError => error
      execution_result(failed(code: "persistence_error", error_class: error.class.name))
    rescue StandardError => error
      raise unless @scheduled

      execution_result(failed(code: "unexpected_error", error_class: error.class.name))
    end

    private

    def evaluate_due(resort, connection)
      # Ignore any cached candidate reads. The lock owner must see committed
      # changes made by a prior manual/scheduled run before acquiring this lock.
      monitor = connection.uncached do
        resort.reload
        ResortWeatherMonitor.find_by(resort_id: resort.id)
      end
      at = Time.current.utc
      @execution[:evaluation_at] = at
      return successful(code: "pilot_resorts_only") unless EvaluateResort::ALLOWED_RESORT_TYPES.include?(resort.slug)
      return successful(code: "monitor_missing") unless monitor
      return successful(code: "monitor_disabled") unless monitor.enabled?
      return successful(code: "unsupported_provider") unless monitor.provider == "noaa"
      if monitor.last_error_code == "rate_limited" && monitor.next_probe_at && monitor.next_probe_at > at
        return successful(code: "rate_limited", retry_at: monitor.next_probe_at)
      end

      detailed_due = monitor.next_check_at.nil? || monitor.next_check_at <= at
      probe_due = monitor.next_probe_at.nil? || monitor.next_probe_at <= at
      return successful(code: "not_due") unless detailed_due || probe_due

      @execution.merge!(invoked: true, mode: detailed_due ? "detailed" : "probe")
      EvaluateResort.call(resort: resort, **@options.merge(persist: true, probe: !detailed_due, evaluation_at: at))
    end

    def execution_result(result)
      return result unless @scheduled

      value = result.value.merge(execution: @execution.dup)
      result.success? ? successful(value) : failed(value)
    end
  end
end
