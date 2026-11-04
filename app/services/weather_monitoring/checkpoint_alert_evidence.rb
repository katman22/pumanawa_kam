# frozen_string_literal: true

module WeatherMonitoring
  # Source rows and their scope/provenance receipt commit together. Signal
  # generation remains separate so its failure cannot erase verified evidence.
  class CheckpointAlertEvidence < ApplicationService
    def initialize(acquisition:, claim:, collection:, clock: -> { Time.current })
      @state, @claim, @collection, @clock = acquisition, claim, collection, clock
    end

    def call
      outcome = nil
      @state.reload.with_lock(requires_new: true) do
        unless @state.owns_claim?(@claim, at: @clock.call.utc)
          outcome = failed(code: "alert_acquisition_superseded")
          next
        end
        at = @clock.call.utc
        recorded = RecordAlertObservations.call(collection: @collection, zone_ids: [], seen_at: at, signal_evidence: true)
        if recorded.failure?
          outcome = recorded
          raise ActiveRecord::Rollback
        end
        unless @state.owns_claim?(@claim, at: @clock.call.utc)
          outcome = failed(code: "alert_acquisition_superseded")
          raise ActiveRecord::Rollback
        end
        receipt = { "version" => 1, "query" => @claim.fetch(:query), "recorded_at" => at.iso8601(6),
          "from" => @claim.fetch(:window).fetch(:from).iso8601, "through" => @claim.fetch(:window).fetch(:through).iso8601,
          "observation_ids" => recorded.value.fetch(:records).map(&:id).uniq.sort }
        @state.update!(pending_evidence: receipt)
        outcome = successful(claim: @claim.merge(version: @state.lock_version, pending_evidence: @state.pending_evidence.deep_dup))
      end
      outcome
    rescue ActiveRecord::ActiveRecordError => error
      failed(code: "alert_evidence_checkpoint_failed", error_class: error.class.name)
    end
  end
end
