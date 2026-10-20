# frozen_string_literal: true

module WeatherMonitoring
  class EvaluateResort < ApplicationService
    def initialize(resort:, persist: false, probe: false, fetch_alerts: true, evaluation_at: Time.current)
      @resort_input, @persist, @probe, @fetch_alerts, @at = resort, persist, probe, fetch_alerts, evaluation_at.utc
    end

    def call
      @resort = @resort_input.is_a?(Resort) ? @resort_input : Resort.find_by(id: @resort_input)
      return failed(code: "resort_missing") unless @resort&.persisted?
      return failed(code: "pilot_resort_only") unless @resort.slug == "brighton"

      @monitor = if @persist
        load_monitor
      else
        ResortWeatherMonitor.find_by(resort_id: @resort.id) || ResortWeatherMonitor.new(resort: @resort)
      end
      return failed(code: "monitor_disabled") if @persist && !@monitor.enabled?

      if @monitor.last_error_code == "rate_limited" && @monitor.next_probe_at && @monitor.next_probe_at > @at
        return failed(code: "rate_limited", retry_at: @monitor.next_probe_at)
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
        return outcome if outcome.failure?
      end
      successful(resort: @resort.slug, persisted: @persist, source_updated_at: @normalized["source_updated_at"],
        snapshot: @snapshot, change: @change, cadence: @cadence, observation: @observation_disposition,
        alerts: alert_diagnostics)
    rescue ActiveRecord::ActiveRecordError => error
      failed(code: "persistence_error", error_class: error.class.name)
    end

    private

    def load_monitor
      ResortWeatherMonitor.find_by(resort_id: @resort.id) || ResortWeatherMonitor.create_or_find_by!(resort_id: @resort.id)
    rescue ActiveRecord::RecordInvalid
      # A uniqueness validation can see a concurrent creator before INSERT.
      ResortWeatherMonitor.find_by!(resort_id: @resort.id)
    end

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
      @monitor.with_lock do
        return failed(code: "superseded_evaluation") unless current_run?
        return failed(code: "older_source_revision") if @monitor.last_source_updated_at && Time.iso8601(@normalized["source_updated_at"]) < @monitor.last_source_updated_at

        recorded = RecordObservation.call(resort: @resort, normalized: @normalized, snapshot: @snapshot, fetched_at: @at, source_metadata: @metadata)
        return recorded if recorded.failure?

        @observation_disposition = recorded.value[:disposition]
        @monitor.assign_attributes(@cadence.except("reasons"))
        @monitor.assign_attributes(current_forecast_observation: recorded.value[:observation], last_checked_at: @at,
          last_success_at: @at, last_source_updated_at: @normalized["source_updated_at"], mapping: @mapping,
          mapping_checked_at: @mapping_refreshed ? @at : @monitor.mapping_checked_at,
          failure_count: 0, last_error_code: nil, last_error_at: nil,
          last_decision: { "evaluation_at" => @at.iso8601, "reasons" => @cadence["reasons"], "quality" => @snapshot["quality"]["state"], "change" => @change, "alerts" => alert_diagnostics })
        assign_alert_state
        @monitor.save!
      end
      successful(true)
    end

    def current_run?
      @monitor.enabled? && @monitor.lock_version == @version && (!@monitor.last_checked_at || @monitor.last_checked_at <= @at)
    end

    def assign_alert_state
      return unless @alerts&.success? && !@alerts.value[:skipped]

      @monitor.active_alert_identifiers = @alerts.value[:active_identifiers]
      @monitor.last_alert_checked_at = @at
      @monitor.last_decision = @monitor.last_decision.merge("processed_alert_revisions" => @alerts.value.fetch(:revisions, []))
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
  end
end
