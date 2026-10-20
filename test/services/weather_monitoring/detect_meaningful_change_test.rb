require_relative "../../helpers/weather_monitoring_data"

class WeatherMeaningfulChangeTest < Minitest::Test
  include WeatherMonitoringData

  def compare(current, previous, **options)
    result = WeatherMonitoring::DetectMeaningfulChange.call(current: current, previous: previous, evaluation_at: ANCHOR, **options)
    assert result.success?
    result.value
  end

  def test_material_and_trivial_amount_changes
    assert compare(forecast(amount: 12 * 25.4), forecast(amount: 8 * 25.4))["meaningful_change"]
    refute compare(forecast(amount: 2 * 25.4), forecast(amount: 25.4))["meaningful_change"]
    assert compare(forecast(amount: 50.8), forecast)["meaningful_change"]
    assert compare(forecast(amount: 6.5 * 25.4), forecast(amount: 5 * 25.4))["meaningful_change"]
    assert compare(forecast(amount: 7 * 25.4), forecast(amount: 5 * 25.4))["meaningful_change"]
  end

  def test_onset_shift_and_natural_clock_passage
    old = forecast(amount: 100, onset: ANCHOR + 3.days)
    changed = forecast(amount: 100, onset: ANCHOR + 3.days - 6.hours)
    assert_includes compare(changed, old)["reasons"], "onset_shifted"
    same = compare(old, old, previous_evaluation_at: ANCHOR - 1.hour)
    refute_includes same["reasons"], "onset_shifted"
    entering = forecast(amount: 100, onset: ANCHOR + 42.hours)
    assert_includes compare(entering, entering, previous_evaluation_at: ANCHOR - 12.hours)["reasons"], "entered_48h"
  end

  def test_no_baseline_and_different_source_are_unknown
    assert_nil compare(forecast, nil)["meaningful_change"]
    other = forecast.merge("source_key" => "SLC/111,167")
    assert_equal "incompatible_source", compare(other, forecast)["disposition"]
  end

  def test_rewindowing_does_not_count_elapsed_snow_as_revision
    data = forecast(amount: 100, onset: ANCHOR)
    at = ANCHOR + 7.hours
    result = WeatherMonitoring::DetectMeaningfulChange.call(current: data, previous: data, evaluation_at: at, previous_evaluation_at: ANCHOR)
    refute result.value["meaningful_change"]
  end
  def test_active_transition_and_policy_override
    data = forecast(amount: 100, onset: ANCHOR)
    result = compare(data, data, previous_evaluation_at: ANCHOR - 1.hour)
    assert_includes result["reasons"], "forecast_became_active"
    refute compare(forecast(amount: 60), forecast, policy: { absolute_mm: 100 })["meaningful_change"]
  end
end
