require_relative "../../helpers/weather_monitoring_data"

class WeatherNormalizeForecastTest < Minitest::Test
  include WeatherMonitoringData

  def test_brighton_units_nulls_and_stable_hash
    data = normalized
    assert_equal "SLC/110,167", data["source_key"]
    assert_equal "2026-10-20T06:31:29Z", data["source_updated_at"]
    assert_equal "mm", data["selected_intervals"]["snowfallAmount"].first["unit"]
    raw = fixture("brighton_grid")
    raw["properties"]["snowfallAmount"]["values"][0]["value"] = nil
    rows = normalized(raw)["selected_intervals"]["snowfallAmount"]
    assert_nil rows.first["value"]
    assert_equal 0, rows[1]["value"]
    assert_equal data["content_sha256"], normalized["content_sha256"]
    raw = fixture("brighton_grid")
    raw["properties"]["snowfallAmount"]["values"].first["value"] = 0.0
    assert_equal data["content_sha256"], normalized(raw)["content_sha256"]
  end

  def test_unit_conversions
    raw = fixture("brighton_grid")
    { "snowfallAmount" => [ "wmoUnit:in", 2, 50.8 ], "snowLevel" => [ "wmoUnit:ft", 1000, 304.8 ],
      "temperature" => [ "wmoUnit:degC", -3, -3 ], "probabilityOfPrecipitation" => [ "wmoUnit:percent", 80, 80 ] }.each do |name, (unit, value, expected)|
      raw["properties"][name]["uom"] = unit
      raw["properties"][name]["values"].first["value"] = value
      assert_equal expected, normalized(raw)["selected_intervals"][name].first["value"]
    end
    raw["properties"]["snowLevel"]["uom"] = "wmoUnit:m"
    assert_equal 1000, normalized(raw)["selected_intervals"]["snowLevel"].first["value"]
  end

  def test_unknown_units_and_invalid_values_are_not_zero
    raw = fixture("brighton_grid")
    raw["properties"]["snowfallAmount"]["uom"] = "mystery"
    data = normalized(raw)
    assert_nil data["selected_intervals"]["snowfallAmount"].first["value"]
    assert_includes data.dig("quality", "layers", "snowfallAmount", "diagnostics"), "unsupported_unit_or_value"
  end

  def test_valid_duration_forms_and_uncertain_accumulations
    %w[PT6H P1D P1DT3H PT30M PT1M30S].each do |duration|
      raw = fixture("brighton_grid")
      raw["properties"]["snowfallAmount"]["values"] = [ { "validTime" => "#{ANCHOR.iso8601}/#{duration}", "value" => 1 } ]
      data = normalized(raw)
      assert_equal duration, data["selected_intervals"]["snowfallAmount"].first["duration"]
      assert_equal duration == "PT6H" ? [] : [ "uncertain_accumulation_duration" ], data.dig("quality", "layers", "snowfallAmount", "diagnostics")
    end
  end

  def test_bad_zero_and_negative_durations_do_not_become_clear
    %w[PT0H PT-6H P nonsense P1M PT].each do |duration|
      raw = fixture("brighton_grid")
      raw["properties"]["snowfallAmount"]["values"] = [ { "validTime" => "#{ANCHOR.iso8601}/#{duration}", "value" => 0 } ]
      data = normalized(raw)
      assert_empty data["selected_intervals"]["snowfallAmount"]
      assert_equal "unknown", snapshot(data)["quality"]["state"]
    end
  end

  def test_sorting_duplicates_overlaps_and_gaps
    raw = fixture("brighton_grid")
    original = normalized(raw)
    rows = raw["properties"]["snowfallAmount"]["values"]
    raw["properties"]["snowfallAmount"]["values"] = (rows.reverse + [ rows.first ])
    assert_equal original["content_sha256"], normalized(raw)["content_sha256"]
    raw["properties"]["snowfallAmount"]["values"] << rows.first.merge("value" => 12)
    assert_includes normalized(raw).dig("quality", "layers", "snowfallAmount", "diagnostics"), "conflicting_overlap"
    raw["properties"]["snowfallAmount"]["values"] = rows.reject.with_index { |_, i| i == 5 }
    assert_equal "partial", snapshot(normalized(raw))["quality"]["state"]
  end
  def test_subsecond_durations_preserve_end_and_source_precision
    raw = fixture("brighton_grid")
    raw["properties"]["temperature"]["values"] = [ { "validTime" => "2026-10-20T16:43:08Z/PT0.5S", "value" => 1 } ]
    row = normalized(raw)["selected_intervals"]["temperature"].first
    assert_equal 0.5, Time.iso8601(row["end_at"]) - Time.iso8601(row["start_at"])
  end
end
