require "test_helper"
require "rake"
require_relative "../helpers/weather_monitoring_data"

class WeatherMonitoringTaskTest < ActiveSupport::TestCase
  include WeatherMonitoringData

  setup do
    @resort = pilot_resort
    load Rails.root.join("lib/tasks/weather_monitoring.rake") unless Rake::Task.task_defined?("weather_monitoring:brighton")
    Rake::Task.define_task(:environment)
    Rake::Task["weather_monitoring:brighton"].reenable
    Rake::Task["weather_monitoring:run_due"].reenable
    @environment = ENV.to_h.slice("PERSIST", "ENABLE", "PROBE")
    %w[PERSIST ENABLE PROBE].each { |key| ENV.delete(key) }
  end

  teardown do
    %w[PERSIST ENABLE PROBE].each { |key| ENV.delete(key) }
    @environment.each { |key, value| ENV[key] = value }
  end

  test "manual task defaults to synchronous dry run" do
    WeatherMonitoring::RunEvaluation.expects(:call).with(resort: @resort, persist: false, probe: false).returns(ServiceResult.new(success: true, value: { resort: "brighton", persisted: false }))
    output, = capture_io { Rake::Task["weather_monitoring:brighton"].invoke }
    assert_includes output, "brighton"
    assert_equal 0, ResortWeatherMonitor.count
  end

  test "enable requires persistence and failures exit nonzero" do
    ENV["ENABLE"] = "1"
    error = assert_raises(SystemExit) { capture_io { Rake::Task["weather_monitoring:brighton"].invoke } }
    refute error.success?
    assert_equal 0, ResortWeatherMonitor.count
    ENV.delete("ENABLE")
    Rake::Task["weather_monitoring:brighton"].reenable
    WeatherMonitoring::RunEvaluation.stubs(:call).returns(ServiceResult.new(success: false, value: { code: "transport_error" }))
    error = assert_raises(SystemExit) { capture_io { Rake::Task["weather_monitoring:brighton"].invoke } }
    refute error.success?
  end

  test "scheduled no op and successful execution log summaries and exit normally" do
    SecureRandom.stubs(:uuid).returns("scheduled-task-test")
    [ 0, 1 ].each do |invoked|
      Rake::Task["weather_monitoring:run_due"].reenable
      WeatherMonitoring::ScheduledRunner.expects(:call).with(has_key(:run_id)).returns(ServiceResult.new(success: true,
        value: { run_id: "scheduled-task-test", candidate_count: invoked, invoked_count: invoked, successful_count: invoked, failed_count: 0, outcomes: [] }))
      output, error = capture_io { Rake::Task["weather_monitoring:run_due"].invoke }
      messages = output.lines.map { |line| JSON.parse(line) }
      assert_equal %w[weather_monitoring.started weather_monitoring.completed], messages.map { |message| message["event"] }
      assert messages.last["success"]
      assert_equal invoked, messages.last["invoked_count"]
      assert_equal messages.first["run_id"], messages.last["run_id"]
      assert_equal "", error
    end
  end

  test "scheduled task real no op returns complete counters without touching monitors" do
    WeatherMonitoring::RunEvaluation.expects(:call).never
    HTTParty.expects(:get).never
    output = nil
    assert_no_difference [ "ResortWeatherMonitor.count", "WeatherForecastObservation.count" ] do
      output, = capture_io { Rake::Task["weather_monitoring:run_due"].invoke }
    end
    messages = output.lines.map { |line| JSON.parse(line) }
    summary = messages.last
    assert_equal true, summary["success"]
    assert_equal messages.first["run_id"], summary["run_id"]
    %w[candidate_count invoked_count skipped_count successful_count failed_count degraded_count].each do |key|
      assert_equal 0, summary[key]
    end
    assert_equal [], summary["outcomes"]
    assert summary["started_at"]
    assert summary["completed_at"]
  end

  test "scheduled failed result logs summary and exits nonzero" do
    WeatherMonitoring::ScheduledRunner.expects(:call).returns(ServiceResult.new(success: false,
      value: { candidate_count: 1, invoked_count: 1, failed_count: 1, outcomes: [ { status: "failed", reason: "transport_error" } ] }))
    exit_error = nil
    output, = capture_io do
      exit_error = assert_raises(SystemExit) { Rake::Task["weather_monitoring:run_due"].invoke }
    end
    refute exit_error.success?
    message = JSON.parse(output.lines.last)
    assert_equal false, message["success"]
    assert_equal 1, message["failed_count"]
    assert_equal "transport_error", message["outcomes"].first["reason"]
  end

  test "scheduled unexpected exception emits a safe final message and exits nonzero" do
    WeatherMonitoring::ScheduledRunner.expects(:call).raises(ArgumentError, "PRIVATE PROVIDER BODY")
    exit_error = nil
    output, = capture_io do
      exit_error = assert_raises(SystemExit) { Rake::Task["weather_monitoring:run_due"].invoke }
    end
    refute exit_error.success?
    messages = output.lines.map { |line| JSON.parse(line) }
    assert_equal messages.first["run_id"], messages.last["run_id"]
    assert_equal false, messages.last["success"]
    assert_equal "ArgumentError", messages.last["errors"].first["error_class"]
    refute_includes output, "PRIVATE PROVIDER BODY"
  end
end
