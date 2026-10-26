require "test_helper"
require_relative "../../helpers/weather_monitoring_data"

class WeatherMonitoringUpdateTest < ActiveSupport::TestCase
  include WeatherMonitoringData

  setup do
    @resort = pilot_resort
    @monitor = ResortWeatherMonitor.create!(resort: @resort, enabled: true, failure_count: 3,
      last_error_code: "transport_error", last_error_at: ANCHOR - 1.hour,
      active_alert_identifiers: [ "old-alert" ], last_alert_checked_at: ANCHOR - 2.hours,
      last_decision: { "processed_alert_revisions" => [ "old-revision" ] })
    @normalized = normalized
    @snapshot = snapshot(@normalized)
    @mapping = fixture("brighton_points")["properties"].merge("latitude" => @resort.latitude, "longitude" => @resort.longitude)
    @cadence = WeatherMonitoring::EvaluateCadence.call(snapshot: @snapshot, evaluation_at: ANCHOR).value
    @attributes = { last_checked_at: ANCHOR, last_success_at: ANCHOR, last_source_updated_at: @normalized["source_updated_at"],
      mapping: @mapping, mapping_checked_at: ANCHOR, failure_count: 0, last_error_code: nil, last_error_at: nil,
      last_decision: { "evaluation_at" => ANCHOR.iso8601, "quality" => "complete", "reasons" => @cadence["reasons"] } }
    @observations = { resort: @resort, normalized: @normalized, snapshot: @snapshot, fetched_at: ANCHOR,
      source_metadata: { "source_url" => @mapping["forecastGridData"] } }
    @alerts = success(active_identifiers: [ "new-alert" ], revisions: [ "new-revision" ])
    HTTParty.stubs(:get).raises("Unexpected live NOAA request")
  end

  def success(value)
    ServiceResult.new(success: true, value: value)
  end

  def update(**overrides)
    WeatherMonitoring::Update.call(**{ monitor: @monitor, normalized: @normalized, at: ANCHOR, cadence: @cadence,
      alerts: @alerts, monitor_attributes: @attributes, observations: @observations, version: @monitor.lock_version }.merge(overrides))
  end

  def assert_rejected(code, **overrides)
    @monitor.reload
    historical = WeatherMonitoring::RecordObservation.call(**@observations).value[:observation]
    historical_attributes = historical.attributes
    @monitor.update!(current_forecast_observation: historical)
    before = @monitor.reload.attributes
    WeatherMonitoring::RecordObservation.expects(:call).never
    assert_no_difference "WeatherForecastObservation.count" do
      result = update(**overrides)
      assert_instance_of ServiceResult, result
      assert result.failure?
      assert_equal code, result.value[:code]
    end
    assert_equal before, @monitor.reload.attributes
    assert_equal historical_attributes, historical.reload.attributes
  end

  test "successful persistence applies evidence cadence mapping times and resets failures" do
    result = nil
    assert_difference "WeatherForecastObservation.count", 1 do
      result = update
    end
    assert_instance_of ServiceResult, result
    assert result.success?, result.value.inspect
    assert_equal "created", result.value[:observation_disposition]
    monitor = @monitor.reload
    assert_equal @resort.id, monitor.current_forecast_observation.resort_id
    assert_equal @normalized["content_sha256"], monitor.current_forecast_observation.content_sha256
    assert_equal @mapping["forecastGridData"], monitor.current_forecast_observation.source_metadata["source_url"]
    %w[monitoring_level next_check_at next_probe_at acceleration_until].each do |field|
      @cadence[field].nil? ? assert_nil(monitor.public_send(field)) : assert_equal(@cadence[field], monitor.public_send(field))
    end
    assert_equal ANCHOR, monitor.last_checked_at
    assert_equal ANCHOR, monitor.last_success_at
    assert_equal Time.iso8601(@normalized["source_updated_at"]), monitor.last_source_updated_at
    assert_equal @mapping, monitor.mapping
    assert_equal ANCHOR, monitor.mapping_checked_at
    assert_equal 0, monitor.failure_count
    assert_nil monitor.last_error_code
    assert_nil monitor.last_error_at
  end

  test "unchanged revision is reused without changing immutable history" do
    assert update.success?
    original = @monitor.reload.current_forecast_observation
    before = original.attributes
    assert_no_difference "WeatherForecastObservation.count" do
      result = update
      assert result.success?
      assert_equal "existing", result.value[:observation_disposition]
    end
    assert_equal original.id, @monitor.reload.current_forecast_observation_id
    assert_equal before, original.reload.attributes
    assert original.readonly?
  end

  test "changed content creates new evidence while preserving previous history" do
    assert update.success?
    original = @monitor.reload.current_forecast_observation
    before = original.attributes
    raw = fixture("brighton_grid")
    raw["properties"]["snowfallAmount"]["values"][14]["value"] += 25.4
    data = normalized(raw)
    assert_difference "WeatherForecastObservation.count", 1 do
      result = update(normalized: data, observations: @observations.merge(normalized: data, snapshot: snapshot(data)))
      assert result.success?
    end
    refute_equal original.id, @monitor.reload.current_forecast_observation_id
    assert_equal before, original.reload.attributes
    assert @monitor.current_forecast_observation.readonly?
  end

  test "disabled monitor is rejected without persistence" do
    @monitor.update!(enabled: false)
    assert_rejected("superseded_evaluation")
  end

  test "stale captured version is rejected after locked reload" do
    stale_version = @monitor.lock_version
    ResortWeatherMonitor.find(@monitor.id).update!(next_probe_at: ANCHOR + 1.hour)
    assert_rejected("superseded_evaluation", version: stale_version)
  end

  test "evaluation older than completed check is rejected" do
    @monitor.update!(last_checked_at: ANCHOR + 1.second)
    assert_rejected("superseded_evaluation")
  end

  test "older NOAA revision is rejected" do
    @monitor.update!(last_source_updated_at: Time.iso8601(@normalized["source_updated_at"]) + 1.second)
    assert_rejected("older_source_revision")
  end

  test "successful alert probe stores identifiers timestamp and processed revisions" do
    assert update.success?
    assert_equal [ "new-alert" ], @monitor.reload.active_alert_identifiers
    assert_equal ANCHOR, @monitor.last_alert_checked_at
    assert_equal [ "new-revision" ], @monitor.last_decision["processed_alert_revisions"]
    assert_equal ANCHOR.iso8601, @monitor.last_decision["evaluation_at"]
  end

  test "skipped and degraded alerts preserve last successful probe state" do
    [ success(skipped: true), ServiceResult.new(success: false, value: { code: "transport_error" }), nil ].each do |alerts|
      before = @monitor.reload.attributes.slice("active_alert_identifiers", "last_alert_checked_at")
      processed = @monitor.last_decision["processed_alert_revisions"]
      assert update(alerts: alerts).success?
      assert_equal before, @monitor.reload.attributes.slice("active_alert_identifiers", "last_alert_checked_at")
      assert_equal processed, @monitor.last_decision["processed_alert_revisions"]
    end
  end

  test "monitor save failure rolls back newly recorded observation even inside outer transaction" do
    before = @monitor.attributes
    @monitor.expects(:save!).raises(ActiveRecord::RecordInvalid.new(@monitor))
    ResortWeatherMonitor.transaction(requires_new: true) do
      assert_no_difference "WeatherForecastObservation.count" do
        result = update
        assert result.failure?
        assert_equal({ code: "persistence_error", error_class: "ActiveRecord::RecordInvalid" }, result.value)
      end
    end
    assert_equal before, @monitor.reload.attributes
  end

  test "database exceptions return failures without changing evidence or monitor" do
    before = @monitor.attributes
    WeatherMonitoring::RecordObservation.expects(:call).raises(ActiveRecord::StatementInvalid, "test database failure")
    assert_no_difference "WeatherForecastObservation.count" do
      result = update
      assert result.failure?
      assert_equal "persistence_error", result.value[:code]
      assert_equal "ActiveRecord::StatementInvalid", result.value[:error_class]
    end
    assert_equal before, @monitor.reload.attributes
  end

  test "recorder failure result is propagated without changing state" do
    failure = ServiceResult.new(success: false, value: { code: "observation_invalid" })
    before = @monitor.attributes
    WeatherMonitoring::RecordObservation.expects(:call).returns(failure)
    assert_no_difference "WeatherForecastObservation.count" do
      assert_same failure, update
    end
    assert_equal before, @monitor.reload.attributes
  end

  test "recorder failure after a write cannot leave partial observation evidence" do
    failure = ServiceResult.new(success: false, value: { code: "observation_invalid" })
    before = @monitor.attributes
    WeatherMonitoring::RecordObservation.expects(:call).with do |**attributes|
      WeatherForecastObservation.create!(resort: attributes[:resort], provider: "noaa", source_key: @normalized["source_key"],
        source_updated_at: @normalized["source_updated_at"], first_fetched_at: ANCHOR,
        forecast_window_start: ANCHOR, forecast_window_end: ANCHOR + 120.hours,
        normalization_version: 1, content_sha256: @normalized["content_sha256"])
      true
    end.returns(failure)
    assert_no_difference "WeatherForecastObservation.count" do
      assert_same failure, update
    end
    assert_equal before, @monitor.reload.attributes
  end

  test "unexpected errors are reported as failure and roll back evidence" do
    error = NoMethodError.new("test programming defect")
    @monitor.expects(:save!).raises(error)
    Rails.error.expects(:report).with(error, handled: true)
    before = @monitor.attributes
    assert_no_difference "WeatherForecastObservation.count" do
      result = update
      assert result.failure?
      assert_equal({ code: "unexpected_error", error_class: "NoMethodError" }, result.value)
    end
    assert_equal before, @monitor.reload.attributes
  end
  test "real recorder validation failure returns failure without writes" do
    invalid = @normalized.merge("content_sha256" => "invalid")
    before = @monitor.attributes
    assert_no_difference "WeatherForecastObservation.count" do
      result = update(normalized: invalid, observations: @observations.merge(normalized: invalid))
      assert result.failure?
      assert_equal "observation_invalid", result.value[:code]
    end
    assert_equal before, @monitor.reload.attributes
  end

  test "successful empty alert probe replaces previous active state" do
    assert update(alerts: success(active_identifiers: [], revisions: [])).success?
    assert_empty @monitor.reload.active_alert_identifiers
    assert_equal ANCHOR, @monitor.last_alert_checked_at
    assert_equal [], @monitor.last_decision["processed_alert_revisions"]
  end

  test "error after real monitor save rolls back both monitor and observation inside caller transaction" do
    before = @monitor.attributes
    save = @monitor.method(:save!)
    @monitor.define_singleton_method(:save!) do
      save.call
      raise ActiveRecord::StatementInvalid, "simulated failure after SQL write"
    end
    ResortWeatherMonitor.transaction(requires_new: true) do
      assert_no_difference "WeatherForecastObservation.count" do
        result = update
        assert result.failure?
        assert_equal "persistence_error", result.value[:code]
      end
      assert_equal before, ResortWeatherMonitor.find(@monitor.id).attributes
    end
  end

  test "locking and uniqueness database exceptions are failures" do
    [ ActiveRecord::Deadlocked, ActiveRecord::StaleObjectError, ActiveRecord::RecordNotUnique ].each do |type|
      before = @monitor.reload.attributes
      WeatherMonitoring::RecordObservation.expects(:call).raises(type)
      assert_no_difference "WeatherForecastObservation.count" do
        result = update
        assert result.failure?
        assert_equal "persistence_error", result.value[:code]
        assert_equal type.name, result.value[:error_class]
      end
      assert_equal before, @monitor.reload.attributes
    end
  end
end
