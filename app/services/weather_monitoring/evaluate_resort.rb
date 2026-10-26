# frozen_string_literal: true

module WeatherMonitoring
  class EvaluateResort < ApplicationService
    attr_reader :resort_input, :persist, :probe, :fetch_alerts, :at, :monitor

    RESORT_MISSING = "resort_missing"
    RESORT_NOT_ALLOWED = "pilot_resorts_only"
    ALLOWED_RESORT_TYPES = [ "brighton" ]
    MONITOR_CLASS = ResortWeatherMonitor

    def initialize(resort:, persist: false, probe: false, fetch_alerts: true, evaluation_at: Time.current)
      @resort_input, @persist, @probe, @fetch_alerts, @at = resort, persist, probe, fetch_alerts, evaluation_at.utc
    end

    def call
      return failed(code: RESORT_MISSING) unless resort&.persisted?
      return failed(code: RESORT_NOT_ALLOWED) unless ALLOWED_RESORT_TYPES.include?(resort.slug)
      @monitor = resolve_monitor

      return failed(code: "monitor_disabled") if persist && !monitor.enabled?

      if monitor.last_error_code == "rate_limited" && monitor.next_probe_at && monitor.next_probe_at > at
        return failed(code: "rate_limited", retry_at: monitor.next_probe_at)
      end

      @version = @monitor.lock_version
      @previous = @monitor.current_forecast_observation
      mapping_result = mapping
      return record_failure(mapping_result) if mapping_result.failure?

      @mapping = mapping_result.value
      @alerts = alerts
      grid = fetch_grid
      if grid.failure? && %w[http_404 invalid_grid].include?(grid.value[:code])
        refreshed = Noaa::Forecast::Point.call(latitude: @resort.latitude, longitude: @resort.longitude)
        if refreshed.success?
          @mapping, @mapping_refreshed = refreshed.value, true
          grid = fetch_grid(use_retained: false)
        end
      end
      return record_failure(grid) if grid.failure?

      normalized = if grid.value["status"] == 304
                     successful(grid.value.dig("body", "normalized"))
      else
                     NormalizeForecast.call(raw: grid.value["body"])
      end
      return record_failure(normalized) if normalized.failure?

      @normalized = normalized.value
      snapshot = ForecastSnapshot.call(normalized: @normalized, evaluation_at: @at)
      return record_failure(snapshot) if snapshot.failure?

      @snapshot = snapshot.value
      previous_at = @monitor.last_decision["evaluation_at"]
      change = DetectMeaningfulChange.call(current: @normalized, previous: @previous&.normalized, evaluation_at: @at,
                                           previous_evaluation_at: previous_at && Time.iso8601(previous_at))
      return record_failure(change) if change.failure?

      @change = change.value
      changed = @previous && (@previous.content_sha256 != @normalized["content_sha256"] || @previous.source_key != @normalized["source_key"])
      cadence = EvaluateCadence.call(snapshot: @snapshot, evaluation_at: @at, change: @change,
                                     acceleration_until: @monitor.acceleration_until, alert_wake: alert_wake?,
                                     existing_next_check_at: @monitor.next_check_at, probe: @probe, grid_changed: changed)
      return record_failure(cadence) if cadence.failure?

      @cadence = cadence.value
      @metadata = (@normalized["source_metadata"] || {}).merge("requested_coordinates" => { "latitude" => @resort.latitude, "longitude" => @resort.longitude },
                                                               "source_url" => @mapping["forecastGridData"], "http_headers" => source_headers(grid))
      @observation_disposition = "dry_run"
      if @persist
        outcome = commit_success
        if outcome.failure?
          return outcome if outcome.value[:code] == "superseded_evaluation"

          # Update may have rolled back after changing this Ruby object's
          # attributes (including lock_version). Reload committed truth before
          # failure bookkeeping; the captured run version still guards writes.
          @monitor.reload
          return record_failure(outcome)
        end
        @observation_disposition = outcome.value[:observation_disposition]
      end
      successful(resort: @resort.slug, persisted: @persist, source_updated_at: @normalized["source_updated_at"],
                 snapshot: @snapshot, change: @change, cadence: @cadence, observation: @observation_disposition,
                 alerts: alert_diagnostics)
    rescue ActiveRecord::ActiveRecordError => error
      failed(code: "persistence_error", error_class: error.class.name)
    end

    private

    def mapping
      stored = @monitor.mapping
      valid = @monitor.mapping_checked_at && @monitor.mapping_checked_at > @at - 1.day &&
        stored["latitude"] == @resort.latitude && stored["longitude"] == @resort.longitude
      return successful(stored) if valid

      @mapping_refreshed = true
      Noaa::Forecast::Point.call(latitude: @resort.latitude, longitude: @resort.longitude)
    end

    def fetch_grid(use_retained: true)
      compatible = use_retained && @previous && @previous.source_key == "#{@mapping['gridId']}/#{@mapping['gridX']},#{@mapping['gridY']}" &&
        @previous.source_metadata["requested_coordinates"] == { "latitude" => @resort.latitude, "longitude" => @resort.longitude }
      headers = compatible ? @previous.source_metadata.fetch("http_headers", {}) : {}
      validators = { "If-Modified-Since" => headers["last-modified"], "If-None-Match" => headers["etag"] }.compact
      Noaa::Forecast::GridData.call(mapping: @mapping, validators: validators, retained: compatible ? { "normalized" => @previous.normalized } : nil)
    end

    def alerts
      return successful(skipped: true, changed: [], active_identifiers: @monitor.active_alert_identifiers) unless @fetch_alerts

      fetched = Noaa::Alerts::Fetch.call(latitude: @resort.latitude, longitude: @resort.longitude)
      return fetched if fetched.failure?

      RecordAlertObservations.call(collection: fetched.value, zone_ids: [ @mapping.fetch("forecastZone").split("/").last ], seen_at: @at, persist: @persist)
    end

    def alert_wake?
      wake_revisions.any?
    end

    def wake_revisions
      return [] unless @alerts&.success? && !@alerts.value[:skipped]

      @wake_revisions ||= @alerts.value.fetch(:revisions, []) - @monitor.last_decision.fetch("processed_alert_revisions", [])
    end

    def alert_diagnostics
      if @alerts&.success?
        { state: @alerts.value[:skipped] ? "skipped" : "available", active_identifiers: @alerts.value[:active_identifiers], changed: wake_revisions }
      else
        { state: "degraded", error: @alerts&.value }
      end
    end

    def source_headers(grid)
      old = grid.value["status"] == 304 ? @previous.source_metadata.fetch("http_headers", {}) : {}
      old.merge(grid.value["headers"].slice("last-modified", "etag", "cache-control", "date", "expires"))
    end

    # HTTP is finished before this short row lock. Optimistic version + source
    # checks reject slower runs, including concurrent enable/disable operations.
    def commit_success
      WeatherMonitoring::Update.call(
        monitor: monitor,
        normalized: @normalized,
        at: at,
        cadence: @cadence,
        alerts: @alerts,
        monitor_attributes: monitor_update_attributes,
        observations: current_observations,
        version: @version
      )
    end

    def monitor_update_attributes
      last_decision = { "evaluation_at" => at.iso8601, "reasons" => @cadence["reasons"], "quality" => @snapshot["quality"]["state"], "change" => @change, "alerts" => alert_diagnostics }
      {
        last_checked_at: at,
        last_success_at: at,
        last_source_updated_at: @normalized["source_updated_at"],
        mapping: @mapping,
        mapping_checked_at: @mapping_refreshed ? at : monitor.mapping_checked_at,
        failure_count: 0,
        last_error_code: nil,
        last_error_at: nil,
        last_decision: last_decision }
    end

    def current_observations
      { resort: resort, normalized: @normalized, snapshot: @snapshot, fetched_at: at, source_metadata: @metadata }
    end

    def record_failure(result)
      if @persist && @monitor&.persisted?
        @monitor.with_lock do
          return failed(code: "superseded_evaluation") unless current_run?

          retry_at = [ @at + 1.hour, result.value[:retry_at] || @at ].max
          @monitor.next_check_at = alert_wake? ? [ @monitor.next_check_at || @at, @at ].min : retry_at
          @monitor.next_probe_at = retry_at
          @monitor.last_checked_at = @at
          @monitor.failure_count += 1
          @monitor.last_error_code = result.value[:code]
          @monitor.last_error_at = @at
          assign_alert_state
          @monitor.save!
        end
      end
      failed(result.value.merge(alerts: alert_diagnostics))
    end

    def current_run?
      monitor.enabled? && monitor.lock_version == @version && (!monitor.last_checked_at || monitor.last_checked_at <= at)
    end

    def resort
      @resort ||= resort_input.is_a?(Resort) ?
                    resort_input : Resort.find_by(id: resort_input)
    end

    def resolve_monitor
      persist ? load_monitor : new_monitor
    end

    def load_monitor
      MONITOR_CLASS.find_by(resort_id: resort.id) ||
        MONITOR_CLASS.create_or_find_by!(resort_id: resort.id)
    rescue ActiveRecord::RecordInvalid
      MONITOR_CLASS.find_by!(resort_id: resort.id)
    end

    def new_monitor
      MONITOR_CLASS.find_by(resort_id: resort.id) ||
        MONITOR_CLASS.new(resort: resort)
    end

    def assign_alert_state
      return unless @alerts&.success? && !@alerts.value[:skipped]

      monitor.active_alert_identifiers = @alerts.value[:active_identifiers]
      monitor.last_alert_checked_at = at
      monitor.last_decision = monitor.last_decision.merge("processed_alert_revisions" => @alerts.value.fetch(:revisions, []))
    end
  end
end
