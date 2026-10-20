require "test_helper"
require_relative "../../helpers/weather_monitoring_data"

class WeatherEvaluateResortTest < ActiveSupport::TestCase
  include WeatherMonitoringData

  setup do
    @resort = pilot_resort
    @mapping = fixture("brighton_points")["properties"].merge("latitude" => @resort.latitude, "longitude" => @resort.longitude)
    @grid = fixture("brighton_grid")
    Noaa::Forecast::Point.stubs(:call).returns(success(@mapping))
    Noaa::Forecast::GridData.stubs(:call).returns(success("status" => 200, "body" => @grid, "headers" => { "last-modified" => "Tue, 20 Oct 2026 06:31:29 GMT" }))
    Noaa::Alerts::Fetch.stubs(:call).returns(success("features" => []))
    HTTParty.stubs(:get).raises("Unexpected live NOAA request")
  end

  def success(value)
    ServiceResult.new(success: true, value: value)
  end

  def evaluate(**options)
    WeatherMonitoring::EvaluateResort.call(resort: @resort, evaluation_at: ANCHOR, **options)
  end

  def enabled_monitor
    ResortWeatherMonitor.create!(resort: @resort, enabled: true)
  end

  test "default dry run uses real pipeline and does not write or change Resort" do
    before = @resort.attributes
    assert_no_difference [ "ResortWeatherMonitor.count", "WeatherForecastObservation.count", "WeatherAlertObservation.count" ] do
      result = evaluate
      assert result.success?, result.value.inspect
      assert_in_delta 106.68, result.value.dig(:snapshot, "summary", "snowfall", "amount_mm")
      assert_equal "no_baseline", result.value.dig(:change, "disposition")
      assert_equal ANCHOR + 6.hours, result.value.dig(:cadence, "next_check_at")
    end
    assert_equal before, @resort.reload.attributes
  end

  test "persist requires explicit enable and only Brighton is pilot eligible" do
    assert_equal "monitor_disabled", evaluate(persist: true).value[:code]
    refute ResortWeatherMonitor.find_by!(resort: @resort).enabled?
    other = Resort.create!(resort_name: "Other weather test", slug: "other-weather", latitude: 40, longitude: -111)
    assert_equal "pilot_resort_only", WeatherMonitoring::EvaluateResort.call(resort: other, persist: true).value[:code]
    assert_equal 1, ResortWeatherMonitor.count
  end

  test "persist records coherent evidence and exact repeated fetch still evaluates" do
    monitor = enabled_monitor
    assert_difference "WeatherForecastObservation.count", 1 do
      result = evaluate(persist: true)
      assert result.success?, result.value.inspect
    end
    monitor.reload
    assert_equal ANCHOR, monitor.last_checked_at
    assert_equal "approaching", monitor.monitoring_level
    assert_equal @mapping["forecastGridData"], monitor.current_forecast_observation.source_metadata["source_url"]
    Noaa::Forecast::Point.expects(:call).never
    Noaa::Forecast::GridData.expects(:call).with(has_entries(validators: has_key("If-Modified-Since"), retained: anything, mapping: anything))
      .returns(success("status" => 304, "body" => { "normalized" => monitor.current_forecast_observation.normalized }, "headers" => {}))
    assert_no_difference "WeatherForecastObservation.count" do
      result = evaluate(persist: true)
      assert result.success?, result.value.inspect
      assert_equal "existing", result.value[:observation]
    end
  end

  test "grid failure retains truth and respects retry after" do
    monitor = enabled_monitor
    assert evaluate(persist: true).success?
    observation = monitor.reload.current_forecast_observation_id
    Noaa::Forecast::GridData.stubs(:call).returns(ServiceResult.new(success: false, value: { code: "rate_limited", retry_at: ANCHOR + 2.hours }))
    result = evaluate(persist: true)
    assert result.failure?
    monitor.reload
    assert_equal observation, monitor.current_forecast_observation_id
    assert_equal 1, monitor.failure_count
    assert_equal ANCHOR + 2.hours, monitor.next_check_at
    assert_equal ANCHOR + 2.hours, monitor.next_probe_at
    Noaa::Forecast::Point.expects(:call).never
    Noaa::Forecast::GridData.expects(:call).never
    Noaa::Alerts::Fetch.expects(:call).never
    assert_equal "rate_limited", evaluate(persist: true).value[:code]
  end

  test "alerts failure degrades accelerator but grid still succeeds" do
    enabled_monitor
    Noaa::Alerts::Fetch.stubs(:call).returns(ServiceResult.new(success: false, value: { code: "transport_error" }))
    result = evaluate(persist: true)
    assert result.success?, result.value.inspect
    assert_equal "degraded", result.value[:alerts][:state]
    assert_equal 1, WeatherForecastObservation.count
  end

  test "new ending alert wakes once even when grid fails" do
    monitor = enabled_monitor
    monitor.update!(next_check_at: ANCHOR + 72.hours)
    collection = fixture("ut_winter_alert_updates")
    Noaa::Alerts::Fetch.stubs(:call).returns(success(collection))
    Noaa::Forecast::GridData.stubs(:call).returns(ServiceResult.new(success: false, value: { code: "transport_error" }))
    assert evaluate(persist: true).failure?
    assert_equal 2, WeatherAlertObservation.count
    assert_equal ANCHOR, monitor.reload.next_check_at
    assert evaluate(persist: true).failure?
    assert_equal 2, WeatherAlertObservation.count
    assert_equal ANCHOR + 1.hour, monitor.reload.next_check_at
  end

  test "slow response cannot overwrite concurrent monitor state" do
    monitor = enabled_monitor
    Noaa::Forecast::GridData.stubs(:call).with(anything).returns(success("status" => 200, "body" => @grid, "headers" => {}))
    Noaa::Alerts::Fetch.stubs(:call).with { |**_arguments| monitor.update!(next_check_at: ANCHOR + 7.hours); true }.returns(success("features" => []))
    result = evaluate(persist: true)
    assert_equal "superseded_evaluation", result.value[:code]
    assert_equal ANCHOR + 7.hours, monitor.reload.next_check_at
    assert_equal 0, WeatherForecastObservation.count
  end

  test "changed probe advances detailed due but unchanged probe does not delay it" do
    monitor = enabled_monitor
    assert evaluate(persist: true).success?
    due = monitor.reload.next_check_at
    assert evaluate(persist: true, probe: true).success?
    assert_equal due, monitor.reload.next_check_at
    @grid["properties"]["snowfallAmount"]["values"][14]["value"] += 1
    assert evaluate(persist: true, probe: true).success?
    assert_equal ANCHOR, monitor.reload.next_check_at
  end
  test "full provider to persistence pipeline uses captured HTTP fixtures" do
    enabled_monitor
    Noaa::Forecast::Point.unstub(:call)
    Noaa::Forecast::GridData.unstub(:call)
    Noaa::Alerts::Fetch.unstub(:call)
    HTTParty.expects(:get).with("https://api.weather.gov/points/40.5986,-111.5845", anything).returns(http_response(fixture("brighton_points")))
    HTTParty.expects(:get).with("https://api.weather.gov/alerts?active=true&point=40.5986,-111.5845", anything).returns(http_response(fixture("brighton_active_alerts")))
    HTTParty.expects(:get).with(@mapping["forecastGridData"], anything).returns(http_response(@grid))
    result = evaluate(persist: true)
    assert result.success?, result.value.inspect
    assert_in_delta 106.68, WeatherForecastObservation.last.summary.dig("snowfall", "amount_mm")
  end

  test "unknown snowfall never schedules quiet weather" do
    monitor = enabled_monitor
    @grid["properties"].delete("snowfallAmount")
    result = evaluate(persist: true)
    assert result.success?, result.value.inspect
    assert_equal "unknown", monitor.reload.monitoring_level
    assert_equal ANCHOR + 1.hour, monitor.next_check_at
    assert_nil result.value.dig(:snapshot, "summary", "snowfall", "amount_mm")
  end

  test "older NOAA source cannot replace a newer retained revision" do
    monitor = enabled_monitor
    assert evaluate(persist: true).success?
    original = monitor.reload.current_forecast_observation_id
    @grid["properties"]["updateTime"] = "2026-10-20T05:00:00Z"
    result = evaluate(persist: true)
    assert_equal "older_source_revision", result.value[:code]
    assert_equal original, monitor.reload.current_forecast_observation_id
    assert_equal 1, WeatherForecastObservation.count
  end

  test "grid 404 refreshes point mapping once" do
    enabled_monitor
    Noaa::Forecast::GridData.expects(:call).twice.returns(ServiceResult.new(success: false, value: { code: "http_404" }), success("status" => 200, "body" => @grid, "headers" => {}))
    Noaa::Forecast::Point.expects(:call).twice.returns(success(@mapping))
    assert evaluate(persist: true).success?
  end
  test "existing shared alert evidence still wakes an unprocessed monitor once" do
    collection = fixture("ut_winter_alert_updates")
    WeatherMonitoring::RecordAlertObservations.call(collection: collection, zone_ids: [ "UTZ111" ], seen_at: ANCHOR)
    monitor = enabled_monitor
    Noaa::Alerts::Fetch.stubs(:call).returns(success(collection))
    first = evaluate(persist: true)
    assert first.success?, first.value.inspect
    assert_equal ANCHOR, monitor.reload.next_check_at
    assert_equal 2, monitor.last_decision["processed_alert_revisions"].size
    assert_equal 2, first.value[:alerts][:changed].size
    second = evaluate(persist: true)
    assert second.success?, second.value.inspect
    assert_empty second.value[:alerts][:changed]
    assert_equal ANCHOR + 6.hours, monitor.reload.next_check_at
  end
end
