# frozen_string_literal: true

module WeatherMonitoring
  # Composition only: independent schedulers keep their own policy/state.
  class ScheduledRun < ApplicationService
    def initialize(run_id: SecureRandom.uuid)
      @run_id = run_id
    end

    def call
      forecast = safely { ScheduledRunner.call(run_id: @run_id) }
      alerts = safely { ScheduledAlertRunner.call }
      value = forecast.value.merge(run_id: @run_id, forecast_success: forecast.success?, alert_acquisition: alerts.to_h)
      forecast.success? && alerts.success? ? successful(value) : failed(value)
    end

    private

    def safely
      yield
    rescue StandardError => error
      failed(errors: [ { code: "scheduled_branch_error", error_class: error.class.name } ])
    end
  end
end
