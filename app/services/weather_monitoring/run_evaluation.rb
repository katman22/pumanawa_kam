# frozen_string_literal: true

module WeatherMonitoring
  # Operational entry point shared by manual and future scheduled runs. Session
  # locks require a direct/session-compatible PostgreSQL connection, not
  # transaction-mode pooling. No transaction is held during provider requests.
  class RunEvaluation < ApplicationService
    def initialize(resort:, **options)
      @resort_input, @options = resort, options
    end

    def call
      resort = @resort_input.is_a?(Resort) ? @resort_input : Resort.find_by(id: @resort_input)
      return failed(code: EvaluateResort::RESORT_MISSING) unless resort&.persisted?
      return failed(code: EvaluateResort::RESORT_NOT_ALLOWED) unless EvaluateResort::ALLOWED_RESORT_TYPES.include?(resort.slug)

      ResortWeatherMonitor.connection_pool.with_connection do |connection|
        # Session advisory locks survive transaction rollback. Refuse enclosing
        # transactions so callers cannot accidentally hold one across HTTP.
        return failed(code: "evaluation_transaction_open") if connection.transaction_open?

        # A stable, positive 60-bit key, shared across Ruby processes. Do not use
        # Ruby's process-randomized String#hash for a database lock identity.
        key = Digest::SHA256.hexdigest("weather_monitoring:resort:#{resort.id}").first(15).to_i(16)
        # These SELECTs have side effects and must never use Rails' query cache.
        acquired = connection.uncached { connection.select_value("SELECT pg_try_advisory_lock(#{key})") }
        return failed(code: "evaluation_busy") unless acquired

        begin
          EvaluateResort.call(resort: resort, **@options)
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
      failed(code: "persistence_error", error_class: error.class.name)
    end
  end
end
