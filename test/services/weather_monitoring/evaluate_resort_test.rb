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
    assert_equal WeatherMonitoring::EvaluateResort::RESORT_NOT_ALLOWED, WeatherMonitoring::EvaluateResort.call(resort: other, persist: true).value[:code]
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
  test "object and id resolution share pipeline while missing and unsaved resorts are rejected" do
    result = WeatherMonitoring::EvaluateResort.call(resort: @resort.id, evaluation_at: ANCHOR)
    assert result.success?, result.value.inspect
    assert_equal @resort.slug, result.value[:resort]
    Noaa::Forecast::Point.expects(:call).never
    [ -1, nil, Resort.new(slug: "brighton") ].each do |input|
      result = WeatherMonitoring::EvaluateResort.call(resort: input, evaluation_at: ANCHOR)
      assert result.failure?
      assert_equal WeatherMonitoring::EvaluateResort::RESORT_MISSING, result.value[:code]
    end
  end

  test "dry run never delegates persistence and fetches alerts once" do
    WeatherMonitoring::Update.expects(:call).never
    Noaa::Alerts::Fetch.expects(:call).once.returns(success("features" => []))
    result = evaluate
    assert result.success?
    assert_equal "dry_run", result.value[:observation]
    assert_empty ResortWeatherMonitor.where(resort: @resort)
  end

  test "alert fetch can be explicitly skipped" do
    Noaa::Alerts::Fetch.expects(:call).never
    result = evaluate(fetch_alerts: false)
    assert result.success?
    assert_equal "skipped", result.value[:alerts][:state]
  end

  test "persistent orchestration delegates complete inputs and returns Update disposition" do
    monitor = enabled_monitor
    Noaa::Alerts::Fetch.expects(:call).once.returns(success("features" => []))
    original = monitor.attributes
    WeatherMonitoring::Update.expects(:call).once.with do |**inputs|
      assert_equal monitor.id, inputs[:monitor].id
      assert_equal monitor.lock_version, inputs[:version]
      assert_equal ANCHOR, inputs[:at]
      assert_equal "SLC/110,167", inputs[:normalized]["source_key"]
      assert_equal ANCHOR + 6.hours, inputs[:cadence]["next_check_at"]
      assert inputs[:alerts].success?
      attributes = inputs[:monitor_attributes]
      assert_equal ANCHOR, attributes[:last_checked_at]
      assert_equal ANCHOR, attributes[:last_success_at]
      assert_equal @mapping, attributes[:mapping]
      assert_equal ANCHOR, attributes[:mapping_checked_at]
      assert_equal "2026-10-20T06:31:29Z", attributes[:last_source_updated_at]
      assert_equal 0, attributes[:failure_count]
      assert_nil attributes[:last_error_code]
      assert_nil attributes[:last_error_at]
      assert_equal "complete", attributes[:last_decision]["quality"]
      assert_equal "no_baseline", attributes[:last_decision]["change"]["disposition"]
      evidence = inputs[:observations]
      assert_equal @resort, evidence[:resort]
      assert_equal ANCHOR, evidence[:fetched_at]
      assert_same inputs[:normalized], evidence[:normalized]
      assert_in_delta 106.68, evidence[:snapshot].dig("summary", "snowfall", "amount_mm")
      assert_equal @mapping["forecastGridData"], evidence[:source_metadata]["source_url"]
      assert_equal({ "latitude" => @resort.latitude, "longitude" => @resort.longitude }, evidence[:source_metadata]["requested_coordinates"])
      true
    end.returns(success(observation_disposition: "delegated-test-disposition"))
    assert_no_difference "WeatherForecastObservation.count" do
      result = evaluate(persist: true)
      assert result.success?
      assert_equal "delegated-test-disposition", result.value[:observation]
    end
    assert_equal original, monitor.reload.attributes
  end

  test "Update failure result propagates unchanged" do
    enabled_monitor
    failure = ServiceResult.new(success: false, value: { code: "superseded_evaluation" })
    WeatherMonitoring::Update.expects(:call).once.returns(failure)
    assert_same failure, evaluate(persist: true)
  end

  test "mapping cache expires or refreshes on coordinate changes" do
    monitor = enabled_monitor
    [ { mapping_checked_at: ANCHOR - 2.days, mapping: @mapping },
      { mapping_checked_at: ANCHOR, mapping: @mapping.merge("latitude" => 0) } ].each do |attributes|
      monitor.update!(**attributes)
      Noaa::Forecast::Point.expects(:call).once.returns(success(@mapping))
      WeatherMonitoring::Update.expects(:call).with do |**inputs|
        assert_equal ANCHOR, inputs[:monitor_attributes][:mapping_checked_at]
        true
      end.returns(success(observation_disposition: "existing"))
      assert evaluate(persist: true).success?
    end
  end

  test "compatible retained grid uses conditional headers and bypasses normalization on 304" do
    monitor = enabled_monitor
    assert evaluate(persist: true).success?
    observation = monitor.reload.current_forecast_observation
    monitor.update!(mapping_checked_at: ANCHOR - 1.hour)
    Noaa::Forecast::Point.expects(:call).never
    WeatherMonitoring::NormalizeForecast.expects(:call).never
    Noaa::Forecast::GridData.expects(:call).with do |**inputs|
      assert_equal "Tue, 20 Oct 2026 06:31:29 GMT", inputs[:validators]["If-Modified-Since"]
      assert_equal observation.normalized, inputs[:retained]["normalized"]
      true
    end.returns(success("status" => 304, "body" => { "normalized" => observation.normalized }, "headers" => {}))
    WeatherMonitoring::Update.expects(:call).with do |**inputs|
      assert_equal ANCHOR - 1.hour, inputs[:monitor_attributes][:mapping_checked_at]
      true
    end.returns(success(observation_disposition: "existing"))
    result = evaluate(persist: true)
    assert result.success?
    assert_in_delta 106.68, result.value.dig(:snapshot, "summary", "snowfall", "amount_mm")
    assert_equal "compared", result.value[:change]["disposition"]
  end

  test "cadence receives requested probe mode and changed grid evidence" do
    monitor = enabled_monitor
    assert evaluate(persist: true).success?
    @grid["properties"]["snowfallAmount"]["values"][14]["value"] += 1
    [ true, false ].each do |probe|
      cadence = { "monitoring_level" => "approaching", "next_check_at" => ANCHOR + 6.hours, "next_probe_at" => ANCHOR + 12.hours, "reasons" => [] }
      WeatherMonitoring::EvaluateCadence.expects(:call).with do |**inputs|
        assert_equal probe, inputs[:probe]
        assert_equal true, inputs[:grid_changed]
        assert_equal monitor.reload.next_check_at, inputs[:existing_next_check_at]
        assert_equal "compared", inputs[:change]["disposition"]
        true
      end.returns(success(cadence))
      assert evaluate(probe: probe).success?
      WeatherMonitoring::EvaluateCadence.unstub(:call)
    end
  end

  test "provider normalization snapshot change and cadence failures propagate without Update" do
    WeatherMonitoring::Update.expects(:call).never
    failure = ServiceResult.new(success: false, value: { code: "test_stage_failure" })
    [ Noaa::Forecast::Point, Noaa::Forecast::GridData, WeatherMonitoring::NormalizeForecast,
      WeatherMonitoring::ForecastSnapshot, WeatherMonitoring::DetectMeaningfulChange, WeatherMonitoring::EvaluateCadence ].each do |stage|
      stage.expects(:call).once.returns(failure)
      result = evaluate
      assert result.failure?
      assert_equal "test_stage_failure", result.value[:code]
      stage.unstub(:call)
      Noaa::Forecast::Point.stubs(:call).returns(success(@mapping))
      Noaa::Forecast::GridData.stubs(:call).returns(success("status" => 200, "body" => @grid, "headers" => {}))
    end
  end

  test "legacy persisted header arrays are reused as strings without editing historical evidence" do
    stamp, etag = "Tue, 20 Oct 2026 06:31:29 GMT", 'W/"legacy-grid"'
    data = normalized(@grid)
    observation = WeatherMonitoring::RecordObservation.call(resort: @resort, normalized: data, snapshot: snapshot(data), fetched_at: ANCHOR,
      source_metadata: { "source_url" => @mapping["forecastGridData"], "requested_coordinates" => { "latitude" => @resort.latitude, "longitude" => @resort.longitude },
        "http_headers" => { "last-modified" => [ stamp ], "etag" => [ etag ] } }).value[:observation]
    monitor = enabled_monitor
    monitor.update!(mapping: @mapping, mapping_checked_at: ANCHOR, current_forecast_observation: observation)
    original = observation.attributes
    Noaa::Forecast::Point.expects(:call).never
    Noaa::Forecast::GridData.unstub(:call)
    WeatherMonitoring::NormalizeForecast.expects(:call).never
    HTTParty.expects(:get).once.with do |url, options|
      assert_equal @mapping["forecastGridData"], url
      assert_equal stamp, options[:headers]["If-Modified-Since"]
      assert_equal etag, options[:headers]["If-None-Match"]
      refute_kind_of Array, options[:headers]["If-Modified-Since"]
      true
    end.returns(http_response("", code: 304, headers: { "Last-Modified" => [ stamp ], "ETag" => [ etag ] }))
    assert_no_difference "WeatherForecastObservation.count" do
      result = evaluate(persist: true)
      assert result.success?, result.value.inspect
      assert_equal "existing", result.value[:observation]
    end
    assert_equal original, observation.reload.attributes
  end
end
