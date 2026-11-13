require "test_helper"
require_relative "../../helpers/weather_monitoring_data"

class WeatherAlertAcquisitionPolicyTest < ActiveSupport::TestCase
  include WeatherMonitoringData

  def policy(**options)
    WeatherMonitoring::AlertAcquisitionPolicy.call(at: ANCHOR, **options)
  end

  test "initial bounded window and independent ten minute cadence" do
    result = policy
    assert result.success?
    assert_equal ANCHOR - 24.hours, result.value[:from]
    assert_equal ANCHOR, result.value[:through]
    assert_equal ANCHOR + 10.minutes, result.value[:next_check_at]
    assert_equal ANCHOR + 5.minutes, result.value[:lease_expires_at]
    assert_equal "initial_window", result.value[:coverage_status]
  end

  test "rolling replay catches late publication and short outage extends to watermark with overlap" do
    assert_equal ANCHOR - 24.hours, policy(watermark: ANCHOR - 10.minutes).value[:from]
    result = policy(watermark: ANCHOR - 36.hours)
    assert_equal ANCHOR - 36.hours - 30.minutes, result.value[:from]
    assert_nil result.value[:coverage_gap]
    assert_equal "bounded_window", result.value[:coverage_status]
  end

  test "long outage reports explicit unrecoverable gap rather than claiming complete recovery" do
    result = policy(watermark: ANCHOR - 8.days)
    assert_equal ANCHOR - 6.days, result.value[:from]
    assert_equal({ "from" => (ANCHOR - 8.days).iso8601, "through" => (ANCHOR - 6.days).iso8601 }, result.value[:coverage_gap])
    assert_equal "recovery_gap", result.value[:coverage_status]
    assert_nil policy(watermark: ANCHOR - 6.days).value[:coverage_gap]
  end

  test "initial unsuccessful window retains its recovery anchor until a watermark exists" do
    initial = ANCHOR - 60.hours
    result = policy(initial_window_start_at: initial)
    assert_equal initial, result.value[:from]
    assert_nil result.value[:coverage_gap]
    old = ANCHOR - 8.days
    result = policy(initial_window_start_at: old)
    assert_equal ANCHOR - 6.days, result.value[:from]
    assert_equal old.iso8601, result.value[:coverage_gap]["from"]
    established = policy(watermark: ANCHOR - 1.hour, initial_window_start_at: old)
    assert_equal ANCHOR - 24.hours, established.value[:from]
    assert_nil established.value[:coverage_gap]
  end

  test "bounded exponential retry honors longer provider Retry After" do
    [ 10.minutes, 20.minutes, 40.minutes, 80.minutes, 160.minutes, 320.minutes, 6.hours ].each_with_index do |delay, index|
      assert_equal ANCHOR + delay, policy(failures: index + 1).value[:retry_at]
    end
    assert_equal ANCHOR + 9.hours, policy(failures: 10, provider_retry_at: ANCHOR + 9.hours).value[:retry_at]
    assert_equal ANCHOR + 6.hours, policy(failures: 1000).value[:retry_at]
  end

  test "API window precision and invalid policies are explicit" do
    result = WeatherMonitoring::AlertAcquisitionPolicy.call(at: ANCHOR + 0.123456)
    assert_equal ANCHOR, result.value[:through]
    assert policy(watermark: ANCHOR + 1.hour).failure?
    assert policy(policy: { interval: 0 }).failure?
    assert policy(policy: { horizon: 1.hour }).failure?
  end
end
