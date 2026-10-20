require_relative "../../helpers/weather_monitoring_data"

class WeatherCadenceTest < Minitest::Test
  include WeatherMonitoringData

  def cadence(data, **options)
    result = WeatherMonitoring::EvaluateCadence.call(snapshot: snapshot(data), evaluation_at: ANCHOR, **options)
    assert result.success?
    result.value
  end

  def test_bands_and_separate_probe_ceiling
    [ [ 0, nil, 72 ], [ 100, 96, 12 ], [ 100, 60, 6 ], [ 100, 24, 4 ], [ 100, 0, 1 ] ].each do |amount, hours, expected|
      result = cadence(forecast(amount: amount, onset: ANCHOR + (hours || 72).hours))
      assert_equal ANCHOR + expected.hours, result["next_check_at"]
      assert_operator result["next_probe_at"], :<=, ANCHOR + 12.hours
    end
    result = cadence(forecast)
    refute_equal result["next_check_at"], result["next_probe_at"]
  end

  def test_unknown_accelerated_and_alert_never_delays
    data = forecast
    data["quality"]["layers"]["snowfallAmount"]["diagnostics"] = [ "missing_layer" ]
    assert_equal "unknown", cadence(data)["monitoring_level"]
    assert_equal ANCHOR + 1.hour, cadence(data)["next_check_at"]
    assert_equal ANCHOR + 1.hour, cadence(data, probe: true, existing_next_check_at: ANCHOR + 72.hours)["next_check_at"]
    changed = cadence(forecast, change: { "meaningful_change" => true, "reasons" => [ "snow_amount_changed" ] })
    assert_equal ANCHOR + 1.hour, changed["next_check_at"]
    assert_equal ANCHOR + 6.hours, changed["acceleration_until"]
    earlier = ANCHOR - 1.minute
    assert_equal earlier, cadence(forecast, alert_wake: true, existing_next_check_at: earlier)["next_check_at"]
  end

  def test_probe_can_only_advance_detailed_due_time
    later = ANCHOR + 72.hours
    assert_equal later, cadence(forecast, probe: true, existing_next_check_at: later)["next_check_at"]
    assert_equal ANCHOR, cadence(forecast, probe: true, existing_next_check_at: later, grid_changed: true)["next_check_at"]
  end
end
