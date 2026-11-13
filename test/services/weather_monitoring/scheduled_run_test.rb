require "test_helper"

class WeatherScheduledRunTest < ActiveSupport::TestCase
  def result(success, value = {})
    ServiceResult.new(success: success, value: value)
  end

  test "independent branches run on both success and failed ServiceResults" do
    [ [ true, true ], [ true, false ], [ false, true ], [ false, false ] ].each do |forecast, alerts|
      WeatherMonitoring::ScheduledRunner.expects(:call).with(run_id: "combined").returns(result(forecast, candidate_count: 0))
      WeatherMonitoring::ScheduledAlertRunner.expects(:call).returns(result(alerts, candidate_count: 0))
      combined = WeatherMonitoring::ScheduledRun.call(run_id: "combined")
      assert_equal forecast && alerts, combined.success?
      assert_equal alerts, combined.value[:alert_acquisition][:success]
      assert_equal "combined", combined.value[:run_id]
      assert_equal 0, combined.value[:candidate_count]
    end
  end

  test "forecast exception cannot prevent alert branch or become success" do
    WeatherMonitoring::ScheduledRunner.expects(:call).raises(ArgumentError, "PRIVATE ERROR")
    WeatherMonitoring::ScheduledAlertRunner.expects(:call).returns(result(true, candidate_count: 0))
    combined = WeatherMonitoring::ScheduledRun.call
    assert combined.failure?
    assert_equal "ArgumentError", combined.value[:errors].first[:error_class]
    assert combined.value[:alert_acquisition][:success]
    refute_includes combined.value.to_json, "PRIVATE ERROR"
  end

  test "alert exception is visible after independent forecast success" do
    WeatherMonitoring::ScheduledRunner.expects(:call).returns(result(true, successful_count: 1))
    WeatherMonitoring::ScheduledAlertRunner.expects(:call).raises(ArgumentError, "PRIVATE ERROR")
    combined = WeatherMonitoring::ScheduledRun.call
    assert combined.failure?
    assert_equal 1, combined.value[:successful_count]
    assert_equal "ArgumentError", combined.value[:alert_acquisition][:value][:errors].first[:error_class]
    refute_includes combined.value.to_json, "PRIVATE ERROR"
  end
end
