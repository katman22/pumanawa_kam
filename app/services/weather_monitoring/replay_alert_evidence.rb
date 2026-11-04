# frozen_string_literal: true

module WeatherMonitoring
  class ReplayAlertEvidence < ApplicationService
    def initialize(evidence:, query:, detected_at:)
      @evidence, @query, @at = evidence, query, detected_at
    end

    def call
      return failed(code: "invalid_pending_alert_evidence") unless valid?

      ProcessAlertCollection.call(observations: @evidence.fetch("observation_ids"), query: @evidence.fetch("query"),
        detected_at: @at, queried_at: Time.iso8601(@evidence.fetch("recorded_at")),
        since: Time.iso8601(@evidence.fetch("from")), through: Time.iso8601(@evidence.fetch("through")))
    end

    private

    def valid?
      return false unless @evidence.is_a?(Hash) && @evidence["version"] == 1 && @evidence["query"] == @query &&
        @evidence["query"].is_a?(Hash) && @evidence["observation_ids"].is_a?(Array) &&
        @evidence["observation_ids"].all? { |id| id.is_a?(Integer) && id.positive? }

      Time.iso8601(@evidence.fetch("recorded_at"))
      Time.iso8601(@evidence.fetch("from")) < Time.iso8601(@evidence.fetch("through"))
    rescue KeyError, ArgumentError, TypeError
      false
    end
  end
end
