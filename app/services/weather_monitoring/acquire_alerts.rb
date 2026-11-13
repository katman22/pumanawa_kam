# frozen_string_literal: true

module WeatherMonitoring
  class AcquireAlerts < ApplicationService
    def initialize(acquisition:, clock: -> { Time.current }, policy: {})
      @state, @clock, @policy = acquisition, clock, policy
    end

    def call
      claimed = ClaimAlertAcquisition.call(acquisition: @state, clock: @clock, policy: @policy)
      return claimed if claimed.failure? || claimed.value[:disposition] == "skipped"

      @claim = claimed.value
      result = acquire
      complete(result)
    rescue StandardError => error
      Rails.error.report(error, handled: true)
      result = failed(code: "unexpected_alert_acquisition_error", error_class: error.class.name)
      @claim ? complete(result) : result
    end

    private

    def acquire
      replayed = nil
      if @claim[:pending_evidence]
        replayed = replay(@claim[:pending_evidence])
        return replayed if replayed.failure?
      end
      query, window = @claim.values_at(:query, :window)
      fetched = Noaa::Alerts::Fetch.call(latitude: query.fetch("latitude"), longitude: query.fetch("longitude"),
        active: false, since: window.fetch(:from), through: window.fetch(:through))
      return fetched if fetched.failure?

      checkpoint = CheckpointAlertEvidence.call(acquisition: @state, claim: @claim, collection: fetched.value, clock: @clock)
      return checkpoint if checkpoint.failure?

      @claim = checkpoint.value.fetch(:claim)
      generated = replay(@claim.fetch(:pending_evidence))
      return generated if generated.failure?

      successful(generated.value.merge(replayed_observation_count: replayed&.value&.fetch(:observation_count, 0) || 0,
        replayed_created_count: replayed&.value&.fetch(:created_count, 0) || 0))
    end

    def replay(evidence)
      ReplayAlertEvidence.call(evidence: evidence, query: @claim.fetch(:query), detected_at: @clock.call.utc)
    end

    def complete(result)
      completed = CompleteAlertAcquisition.call(acquisition: @state, claim: @claim, result: result, clock: @clock, policy: @policy)
      ServiceResult.new(success: completed.success?, value: completed.value.merge(decision: @claim.fetch(:decision)))
    end
  end
end
