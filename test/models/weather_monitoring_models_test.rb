require "test_helper"
require_relative "../helpers/weather_monitoring_data"

class WeatherMonitoringModelsTest < ActiveSupport::TestCase
  include WeatherMonitoringData

  setup do
    @resort = pilot_resort
  end

  test "monitors are disabled by default and unique with nonnegative failures" do
    monitor = ResortWeatherMonitor.create!(resort: @resort)
    refute monitor.enabled?
    assert_nil monitor.next_check_at
    assert_nil monitor.next_probe_at
    refute ResortWeatherMonitor.new(resort: @resort).valid?
    assert_raises(ActiveRecord::RecordNotUnique) { ResortWeatherMonitor.transaction(requires_new: true) { ResortWeatherMonitor.insert_all!([ { resort_id: @resort.id, created_at: Time.current, updated_at: Time.current } ]) } }
    assert_raises(ActiveRecord::StatementInvalid) { ResortWeatherMonitor.transaction(requires_new: true) { monitor.update_columns(failure_count: -1) } }
  end

  test "required resort foreign key is authoritative" do
    assert_raises(ActiveRecord::InvalidForeignKey) { ResortWeatherMonitor.transaction(requires_new: true) { ResortWeatherMonitor.insert_all!([ { resort_id: -1, created_at: Time.current, updated_at: Time.current } ]) } }
  end

  test "history is immutable and not cascade-deleted through resort" do
    data = normalized
    result = WeatherMonitoring::RecordObservation.call(resort: @resort, normalized: data, snapshot: snapshot(data), fetched_at: ANCHOR)
    assert result.success?, result.value.inspect
    record = result.value[:observation]
    assert record.readonly?
    assert_raises(ActiveRecord::ReadOnlyRecord) { record.update!(provider: "changed") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { record.destroy! }
    assert_raises(ActiveRecord::InvalidForeignKey) { @resort.delete }
  end

  test "monitor may only point at its own resort evidence" do
    data = normalized
    record = WeatherMonitoring::RecordObservation.call(resort: @resort, normalized: data, snapshot: snapshot(data), fetched_at: ANCHOR).value[:observation]
    other = Resort.create!(resort_name: "Other test resort", slug: "weather-other", latitude: 40, longitude: -111)
    refute ResortWeatherMonitor.new(resort: other, current_forecast_observation: record).valid?
  end
end
