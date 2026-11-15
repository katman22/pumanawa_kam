require "test_helper"
require_relative "../../helpers/weather_monitoring_data"

class WeatherMobileSummaryTest < ActiveSupport::TestCase
  include WeatherMonitoringData

  setup do
    @resort = pilot_resort
    @monitor = ResortWeatherMonitor.create!(resort: @resort, enabled: true)
    HTTParty.stubs(:get).raises("Unexpected live NOAA request")
  end

  def recorded(raw)
    data = normalized(raw)
    record = WeatherMonitoring::RecordObservation.call(resort: @resort, normalized: data, snapshot: snapshot(data), fetched_at: ANCHOR).value[:observation]
    @monitor.update!(current_forecast_observation: record)
    WeatherMonitoring::MobileSummary.call(resort: @resort, at: ANCHOR).value.fetch(:forecast)
  end

  test "canonical zero and partial lower bounds remain separate" do
    raw = fixture("brighton_grid")
    raw["properties"]["snowfallAmount"]["values"].each { |row| row["value"] = 0 }
    zero = recorded(raw)
    assert_equal 0, zero.dig(:snowfall, :total, :amount_mm)
    assert_equal "complete", zero.dig(:quality, :state)
    raw["properties"]["snowfallAmount"]["values"].select! { |row| Time.iso8601(row["validTime"].split("/").first) < ANCHOR + 4.days }
    partial = recorded(raw)
    assert_equal "partial", partial.dig(:quality, :state)
    assert_nil partial.dig(:snowfall, :total, :amount_mm)
    assert_nil partial.dig(:snowfall, :total, :upper_mm)
    assert partial.dig(:quality, :gaps).any?
  end

  test "future timestamp is identified without rewriting snapshot evidence" do
    data = normalized
    record = WeatherMonitoring::RecordObservation.call(resort: @resort, normalized: data, snapshot: snapshot(data), fetched_at: ANCHOR).value[:observation]
    @monitor.update!(current_forecast_observation: record)
    result = WeatherMonitoring::MobileSummary.call(resort: @resort, at: record.source_updated_at - 1.hour)
    assert result.success?
    assert_equal "future_source", result.value.dig(:forecast, :freshness, :state)
    assert_equal record.forecast_window_start.iso8601, result.value.dig(:forecast, :window, :start_at)
  end

  test "database errors use ServiceResult without private database details" do
    ResortWeatherMonitor.expects(:find_by).raises(ActiveRecord::ConnectionNotEstablished, "PRIVATE DATABASE")
    result = WeatherMonitoring::MobileSummary.call(resort: @resort, at: ANCHOR)
    assert result.failure?
    assert_equal "monitor_summary_unavailable", result.value[:code]
    refute_includes result.to_h.to_json, "PRIVATE DATABASE"
  end
end
