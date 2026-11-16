require_relative "../../helpers/weather_monitoring_data"

class WeatherShortenedZeroAccumulationTest < Minitest::Test
  include WeatherMonitoringData

  def setup
    @raw = fixture("brighton_shortened_accumulation")
    @at = Time.iso8601(@raw.fetch("_fixture").fetch("evaluation_at"))
  end

  def test_reported_leading_zero_pattern_preserves_source_and_complete_forward_bounds
    original = @raw.deep_dup
    data = normalized(@raw)
    assert_equal 2, data["normalization_version"]
    { "snowfallAmount" => 30, "quantitativePrecipitation" => 31 }.each do |name, count|
      rows = data.fetch("selected_intervals").fetch(name)
      assert_equal count, rows.size
      assert_equal [ "2026-11-15T13:00:00Z", "2026-11-15T18:00:00Z", "PT5H", 0, 0, "wmoUnit:mm" ],
        rows.first.values_at("start_at", "end_at", "duration", "source_value", "value", "source_unit")
      assert_empty data.dig("quality", "layers", name, "diagnostics")
    end
    value = snapshot(data, at: @at)
    assert_equal "complete", value.dig("quality", "state")
    assert_equal 432000, value.dig("summary", "snowfall", "coverage_seconds")
    assert_equal [ 100, 125.4 ], value.dig("summary", "snowfall").values_at("lower_mm", "upper_mm")
    assert_nil value.dig("summary", "snowfall", "amount_mm")
    assert_equal snapshot(normalized(fixture("brighton_six_hour_accumulation")), at: @at)["summary"], value["summary"]
    assert_equal original, @raw
  end

  def test_missing_hour_is_a_real_gap_not_extended_zero_coverage
    at = Time.utc(2026, 11, 15, 12)
    @raw["properties"]["updateTime"] = at.iso8601
    result = snapshot(normalized(@raw), at: at)
    snow = result.dig("summary", "snowfall")
    assert_equal "partial", snow["state"]
    assert_equal 119.hours, snow["coverage_seconds"]
    assert_nil snow["amount_mm"]
    assert_nil snow["upper_mm"]
    assert_equal [ { "start_at" => at.iso8601, "end_at" => (at + 1.hour).iso8601 } ], result.dig("quality", "layers", "snowfallAmount", "gaps")
  end

  def test_zero_shortening_inside_window_preserves_gap_and_later_nonzero_accumulation
    row = @raw["properties"]["snowfallAmount"]["values"][4]
    start = Time.iso8601(row["validTime"].split("/").first)
    row["validTime"] = "#{(start + 1.hour).iso8601}/PT5H"
    value = snapshot(normalized(@raw), at: @at)
    assert_equal "partial", value.dig("quality", "state")
    assert_equal 119.hours, value.dig("summary", "snowfall", "coverage_seconds")
    assert_equal 100, value.dig("summary", "snowfall", "lower_mm")
    assert_equal "2026-11-16T18:00:00Z", value.dig("summary", "first_accumulating_snow", "start_at")
  end

  def test_multiple_shortened_zeros_cover_only_the_union_of_actual_intervals
    at = Time.utc(2026, 11, 15, 13)
    @raw["properties"]["updateTime"] = at.iso8601
    @raw["properties"]["snowfallAmount"]["values"] = [
      { "validTime" => "#{at.iso8601}/PT5H", "value" => 0 },
      { "validTime" => "#{(at + 5.hours).iso8601}/PT1H", "value" => 0 },
      *Array.new(19) { |i| { "validTime" => "#{(at + (6 + i * 6).hours).iso8601}/PT6H", "value" => i == 3 ? 25.4 : 0 } }
    ]
    value = snapshot(normalized(@raw), at: at)
    assert_equal "complete", value.dig("quality", "state")
    assert_equal 120.hours, value.dig("summary", "snowfall", "coverage_seconds")
    assert_equal 25.4, value.dig("summary", "snowfall", "amount_mm")
  end

  def test_shortened_zero_crossing_bucket_boundary_has_exact_zero_allocation
    at = Time.utc(2026, 11, 15, 13)
    @raw["properties"]["updateTime"] = at.iso8601
    rows = @raw["properties"]["snowfallAmount"]["values"]
    rows[5]["value"] = 0
    rows[8]["value"] = 100
    rows[4]["validTime"] = "2026-11-16T12:00:00Z/PT5H"
    rows << { "validTime" => "2026-11-16T17:00:00Z/PT1H", "value" => 0 }
    result = snapshot(normalized(@raw), at: at)
    buckets = result.dig("summary", "buckets")
    assert_equal "complete", result.dig("quality", "state")
    assert_equal 0, buckets.first["amount_mm"]
    assert_equal 24.hours, buckets.first["coverage_seconds"]
    # Next six-hour nonzero block crosses the 48h boundary: preserve coupled bounds.
    assert_equal [ 0, 100 ], buckets[1].values_at("lower_mm", "upper_mm")
    assert_equal [ 0, 100 ], buckets[2].values_at("lower_mm", "upper_mm")
    assert_equal 100, result.dig("summary", "snowfall", "amount_mm")
  end

  def test_shortened_zero_at_horizon_is_clipped_without_extra_coverage
    @raw["properties"]["snowfallAmount"]["values"] = Array.new(20) do |i|
      { "validTime" => "#{(@at + i * 6.hours).iso8601}/PT6H", "value" => i == 2 ? 25.4 : 0 }
    end
    @raw["properties"]["snowfallAmount"]["values"][-1] = { "validTime" => "#{(@at + 118.hours).iso8601}/PT5H", "value" => 0 }
    result = snapshot(normalized(@raw), at: @at)
    assert_equal "partial", result.dig("quality", "state")
    assert_equal 116.hours, result.dig("summary", "snowfall", "coverage_seconds")
    assert_equal 25.4, result.dig("summary", "snowfall", "lower_mm")
    assert_nil result.dig("summary", "snowfall", "upper_mm")
  end

  def test_source_exact_zero_requires_recognized_conversion_including_inches
    %w[wmoUnit:mm wmoUnit:in].each do |unit|
      layer = @raw["properties"]["snowfallAmount"]
      layer["uom"] = unit
      data = normalized(@raw)
      assert_empty data.dig("quality", "layers", "snowfallAmount", "diagnostics")
      assert_equal 0, data.dig("selected_intervals", "snowfallAmount", 0, "value")
    end
  end

  def test_shortened_nonzero_null_negative_nonfinite_and_rounded_zero_remain_unknown
    [ 1, nil, -1, -0.00000001, 0.00000001, "0" ].each do |source|
      @raw["properties"]["snowfallAmount"]["values"].first["value"] = source
      data = normalized(@raw)
      assert_includes data.dig("quality", "layers", "snowfallAmount", "diagnostics"), "uncertain_accumulation_duration"
      assert_equal "unknown", snapshot(data, at: @at).dig("quality", "state")
      assert_nil snapshot(data, at: @at).dig("summary", "snowfall", "amount_mm")
    end
  end

  def test_nonfinite_source_values_fail_safely_rather_than_becoming_zero
    [ Float::INFINITY, -Float::INFINITY, Float::NAN ].each do |source|
      @raw["properties"]["snowfallAmount"]["values"].first["value"] = source
      result = WeatherMonitoring::NormalizeForecast.call(raw: @raw)
      assert result.failure?
      assert_equal "invalid_grid", result.value[:code]
    end
  end

  def test_two_shortened_zeros_at_horizon_cover_only_the_120_hour_intersection
    @raw["properties"]["snowfallAmount"]["values"] = Array.new(19) do |i|
      { "validTime" => "#{(@at + i * 6.hours).iso8601}/PT6H", "value" => i == 2 ? 25.4 : 0 }
    end + [ 114, 119 ].map { |hour| { "validTime" => "#{(@at + hour.hours).iso8601}/PT5H", "value" => 0 } }
    value = snapshot(normalized(@raw), at: @at)
    assert_equal "complete", value.dig("quality", "state")
    assert_equal 120.hours, value.dig("summary", "snowfall", "coverage_seconds")
    assert_equal 25.4, value.dig("summary", "snowfall", "amount_mm")
    assert_equal 48.hours, value.dig("summary", "buckets").last["coverage_seconds"]
  end

  def test_unsupported_units_longer_zero_and_malformed_intervals_are_not_exempt
    [ [ "wmoUnit:mm", "PT7H" ], [ "unknown", "PT5H" ], [ "wmoUnit:mm", "PT0H" ], [ "wmoUnit:mm", "PT-5H" ], [ "wmoUnit:mm", "nonsense" ] ].each do |unit, duration|
      raw = @raw.deep_dup
      raw["properties"]["snowfallAmount"] = { "uom" => unit, "values" => [ { "validTime" => "#{@at.iso8601}/#{duration}", "value" => 0 } ] }
      assert_equal "unknown", snapshot(normalized(raw), at: @at).dig("quality", "state")
    end
  end

  def test_zero_exception_does_not_hide_schema_overlap_or_conflicting_values
    [ { "validTime" => "2026-11-15T14:00:00Z/PT1H", "value" => 0 },
      { "validTime" => "2026-11-15T13:00:00Z/PT5H", "value" => 1 },
      { "validTime" => "2026-11-15T13:00:00Z/PT5H" } ].each do |bad|
      raw = @raw.deep_dup
      raw["properties"]["snowfallAmount"]["values"] << bad
      data = normalized(raw)
      refute_empty data.dig("quality", "layers", "snowfallAmount", "diagnostics")
      assert_equal "unknown", snapshot(data, at: @at).dig("quality", "state")
    end
  end
end
