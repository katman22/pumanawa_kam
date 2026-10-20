require_relative "../../helpers/weather_monitoring_data"

class WeatherForecastSnapshotTest < Minitest::Test
  include WeatherMonitoringData

  def test_captured_brighton_snapshot_and_coupled_bucket_bounds
    value = snapshot
    summary = value["summary"]
    assert_equal "complete", value["quality"]["state"]
    assert_equal 432000, summary["snowfall"]["coverage_seconds"]
    assert_in_delta 106.68, summary["snowfall"]["amount_mm"]
    assert_equal [ 0, 0, nil, nil ], summary["buckets"].map { |bucket| bucket["amount_mm"] }
    assert_equal [ 0, 53.34 ], summary["buckets"][2].values_at("lower_mm", "upper_mm")
    assert_equal [ 53.34, 106.68 ], summary["buckets"][3].values_at("lower_mm", "upper_mm")
    assert_equal "2026-10-23T09:00:00Z", summary["first_possible_snow"]["start_at"]
    assert_equal "2026-10-23T12:00:00Z", summary["first_accumulating_snow"]["start_at"]
    assert_equal 99, summary["maximum_pop_percent"]
    assert_operator summary["maximum_pop_percent"], :<=, 100
  end

  def test_partial_fifth_day_and_null_remain_unknown
    raw = fixture("brighton_grid")
    raw["properties"]["snowfallAmount"]["values"].select! { |row| Time.iso8601(row["validTime"].split("/").first) < ANCHOR + 4.days }
    value = snapshot(normalized(raw))
    assert_equal "partial", value["quality"]["state"]
    assert_nil value.dig("summary", "snowfall", "amount_mm")
    assert_nil value.dig("summary", "snowfall", "upper_mm")
    assert value.dig("quality", "layers", "snowfallAmount", "gaps").any?
    raw["properties"]["snowfallAmount"]["values"].each { |row| row["value"] = nil }
    assert_equal "unknown", snapshot(normalized(raw))["quality"]["state"]
  end

  def test_missing_optional_level_does_not_invalidate_snow_but_missing_snow_does
    raw = fixture("brighton_grid")
    raw["properties"].delete("snowLevel")
    value = snapshot(normalized(raw))
    assert_equal "complete", value["quality"]["state"]
    assert_nil value.dig("summary", "snow_level_m", "minimum")
    raw["properties"].delete("snowfallAmount")
    assert_equal "unknown", snapshot(normalized(raw))["quality"]["state"]
  end

  def test_overlap_unknown_unit_and_stale_source_cannot_be_clear
    data = forecast
    data["quality"]["layers"]["snowfallAmount"]["diagnostics"] = [ "conflicting_overlap" ]
    assert_equal "unknown", snapshot(data)["quality"]["state"]
    stale = forecast
    stale["source_updated_at"] = (ANCHOR - 25.hours).iso8601
    assert_equal "unknown", snapshot(stale)["quality"]["state"]
    assert_equal "stale", snapshot(stale)["quality"]["freshness"]
    assert_nil snapshot(stale).dig("summary", "snowfall", "amount_mm")
  end
end
