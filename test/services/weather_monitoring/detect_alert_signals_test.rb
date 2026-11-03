require "test_helper"
require_relative "../../helpers/weather_monitoring_data"

class WeatherDetectAlertSignalsTest < ActiveSupport::TestCase
  include WeatherMonitoringData

  setup do
    @resort = pilot_resort
    @monitor = ResortWeatherMonitor.create!(resort: @resort, enabled: true, next_check_at: ANCHOR + 72.hours, next_probe_at: ANCHOR + 12.hours)
    HTTParty.stubs(:get).raises("Unexpected live NOAA request")
  end

  def detect
    WeatherMonitoring::DetectAlertSignals.call(resort: @resort, detected_at: ANCHOR)
  end

  test "successful point acquisition records general alert signals without changing forecast state" do
    body = fixture("brighton_alert_signal")
    # Point-only alert: no forecast/county identifiers. NOAA's successful point
    # result is the authoritative geographic relationship, not a local GIS guess.
    body["features"][0]["properties"].merge!("affectedZones" => [], "geocode" => {})
    Noaa::Alerts::Fetch.expects(:call).with(latitude: @resort.latitude, longitude: @resort.longitude,
      active: false, since: ANCHOR - 24.hours).twice.returns(ServiceResult.new(success: true, value: body))
    before = @monitor.attributes
    resort_before = @resort.attributes
    assert_difference [ "WeatherAlertObservation.count", "WeatherAlertSignal.count", "WeatherAlertSignalResort.count" ], 1 do
      result = detect
      assert result.success?, result.value.inspect
      assert_equal 1, result.value[:created_count]
    end
    assert_no_difference [ "WeatherAlertObservation.count", "WeatherAlertSignal.count", "WeatherAlertSignalResort.count" ] do
      assert detect.success?
    end
    assert_equal "noaa_point_query", WeatherAlertSignalResort.first.evidence["method"]
    assert_equal before, @monitor.reload.attributes
    assert_equal resort_before, @resort.reload.attributes
    assert_equal 0, WeatherForecastObservation.count
  end

  test "provider failure returns failure without recording or generating evidence" do
    failure = ServiceResult.new(success: false, value: { code: "rate_limited", retry_at: ANCHOR + 1.hour })
    Noaa::Alerts::Fetch.expects(:call).returns(failure)
    WeatherMonitoring::RecordAlertObservations.expects(:call).never
    WeatherMonitoring::GenerateAlertSignals.expects(:call).never
    assert_same failure, detect
    assert_equal 0, WeatherAlertObservation.count
    assert_equal 0, WeatherAlertSignal.count
  end

  test "invalid provider evidence fails and empty response is not cancellation" do
    Noaa::Alerts::Fetch.expects(:call).returns(ServiceResult.new(success: true, value: { "features" => [ nil ] }))
    assert detect.failure?
    Noaa::Alerts::Fetch.expects(:call).returns(ServiceResult.new(success: true, value: { "features" => [] }))
    result = detect
    assert result.success?
    assert_equal [], result.value[:outcomes]
    assert_equal 0, WeatherAlertSignal.count
  end

  test "disabled missing and other resorts do not trigger provider acquisition" do
    Noaa::Alerts::Fetch.expects(:call).never
    @monitor.update!(enabled: false)
    assert_equal "monitor_disabled", detect.value[:code]
    assert_equal "pilot_resorts_only", WeatherMonitoring::DetectAlertSignals.call(resort: nil).value[:code]
    other = Resort.create!(resort_name: "Signal pilot boundary", slug: "signal-pilot-boundary", latitude: 40, longitude: -111)
    assert_equal "pilot_resorts_only", WeatherMonitoring::DetectAlertSignals.call(resort: other).value[:code]
    refute ResortWeatherMonitor.exists?(resort: other)
  end

  test "failed signal transaction keeps recorded source evidence and returns failed ServiceResult" do
    Noaa::Alerts::Fetch.expects(:call).returns(ServiceResult.new(success: true, value: fixture("brighton_alert_signal")))
    failure = ServiceResult.new(success: false, value: { code: "alert_signal_persistence_error" })
    WeatherMonitoring::GenerateAlertSignals.expects(:call).returns(failure)
    assert_same failure, detect
    assert_equal 1, WeatherAlertObservation.count
    assert_equal 0, WeatherAlertSignal.count
  end
end
