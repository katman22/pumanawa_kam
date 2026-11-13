require "test_helper"

class AdminWeatherMonitoringHelperTest < ActionView::TestCase
  include Admin::WeatherMonitoringHelper

  test "exact zero bounded partial unknown and stale snowfall stay distinct" do
    assert_equal "0″", weather_snowfall({ "state" => "complete", "amount_mm" => 0 })
    assert_equal "4.2″", weather_snowfall({ "state" => "complete", "amount_mm" => 106.68 })
    assert_equal "0–2.1″ (bounded)", weather_snowfall({ "state" => "complete", "lower_mm" => 0, "upper_mm" => 53.34 })
    assert_equal "PARTIAL · total unknown", weather_snowfall({ "state" => "partial", "lower_mm" => 0 })
    assert_equal "PARTIAL · at least 1″; total unknown", weather_snowfall({ "state" => "partial", "lower_mm" => 25.4 })
    assert_equal "UNKNOWN", weather_snowfall(nil)
    assert_equal "UNKNOWN", weather_snowfall({ "state" => "unknown", "amount_mm" => 0 })
    assert_equal "STALE · amount unknown", weather_snowfall({ "state" => "complete", "amount_mm" => 0 }, freshness: "stale")
    assert_equal "UNKNOWN", weather_snowfall({ "state" => "complete", "amount_mm" => 0 }, freshness: "future_source")
  end

  test "times identify local zone and retain machine readable UTC" do
    html = weather_time("2026-10-20T16:43:08Z", mapping: { "timeZone" => "America/Denver" })
    assert_includes html, "10:43 MDT"
    assert_includes html, 'datetime="2026-10-20T16:43:08Z"'
    assert_equal "Invalid timestamp", weather_time("bad timestamp")
    assert_equal "Not recorded", weather_time(nil)
  end

  test "unknown state labels and raw content remain escaped" do
    assert_includes weather_state("<script>bad</script>"), "&lt;script&gt;"
    assert_equal "Unsupported unit or value", weather_reason_label("unsupported_unit_or_value")
    assert_equal "UNKNOWN (null)", weather_interval_value({ "value" => nil })
  end

  test "acquisition presentation distinguishes leases and unknown completion without exposing receipts" do
    state = WeatherAlertAcquisition.new(query: { type: "point", latitude: 40.5986, longitude: -111.5845 })
    at = Time.utc(2026, 11, 13, 12)
    assert_equal "Point · 40.5986, -111.5845", weather_acquisition_geography(state)
    assert_equal "None", weather_acquisition_lease(state, at: at)
    assert_equal "Not recorded", weather_acquisition_result(state)
    state.lease_expires_at = at + 1.minute
    assert_equal "Active", weather_acquisition_lease(state, at: at)
    assert_equal "Expired", weather_acquisition_lease(state, at: at + 1.minute)
    state.last_result = { success: false }
    assert_equal "Failed", weather_acquisition_result(state)
    state.last_result = { success: true }
    assert_equal "Successful", weather_acquisition_result(state)
  end
end
