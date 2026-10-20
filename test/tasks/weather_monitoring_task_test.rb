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
    @environment = ENV.to_h.slice("PERSIST", "ENABLE", "PROBE")
    %w[PERSIST ENABLE PROBE].each { |key| ENV.delete(key) }
  end

  teardown do
    %w[PERSIST ENABLE PROBE].each { |key| ENV.delete(key) }
    @environment.each { |key, value| ENV[key] = value }
  end

  test "manual task defaults to synchronous dry run" do
    WeatherMonitoring::EvaluateResort.expects(:call).with(resort: @resort, persist: false, probe: false).returns(ServiceResult.new(success: true, value: { resort: "brighton", persisted: false }))
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
    WeatherMonitoring::EvaluateResort.stubs(:call).returns(ServiceResult.new(success: false, value: { code: "transport_error" }))
    error = assert_raises(SystemExit) { capture_io { Rake::Task["weather_monitoring:brighton"].invoke } }
    refute error.success?
  end
end
