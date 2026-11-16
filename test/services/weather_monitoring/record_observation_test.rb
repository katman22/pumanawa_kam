require "test_helper"
require_relative "../../helpers/weather_monitoring_data"

class WeatherRecordObservationTest < ActiveSupport::TestCase
  include WeatherMonitoringData

  setup { @resort = pilot_resort }

  def record(data, at: ANCHOR)
    result = WeatherMonitoring::RecordObservation.call(resort: @resort, normalized: data, snapshot: snapshot(data, at: at), fetched_at: at)
    assert result.success?, result.value.inspect
    result.value
  end

  test "exact revisions deduplicate without mutating original evidence" do
    data = forecast(amount: 100)
    first = record(data)
    assert_equal "created", first[:disposition]
    again = record(data, at: ANCHOR + 1.hour)
    assert_equal "existing", again[:disposition]
    assert_equal first[:observation].id, again[:observation].id
    assert_equal ANCHOR, again[:observation].first_fetched_at
    assert_equal ANCHOR.iso8601, again[:observation].summary["evaluation_at"]
  end

  test "same timestamp new content and A B A across later revisions are retained" do
    a, b = forecast(amount: 100), forecast(amount: 200)
    first = record(a)[:observation]
    second = record(b)[:observation]
    refute_equal first.id, second.id
    later = a.merge("source_updated_at" => (ANCHOR + 1.hour).iso8601)
    third = record(later, at: ANCHOR + 2.hours)[:observation]
    assert_equal first.content_sha256, third.content_sha256
    refute_equal first.id, third.id
    assert_equal 3, WeatherForecastObservation.count
  end

  test "new timestamp identical content is retained as a source revision" do
    data = forecast
    record(data)
    record(data.merge("source_updated_at" => ANCHOR.iso8601))
    assert_equal 2, WeatherForecastObservation.count
  end

  test "database revision unique index is authoritative" do
    observation = record(forecast)[:observation]
    assert_raises(ActiveRecord::RecordNotUnique) { WeatherForecastObservation.insert_all!([ observation.attributes.except("id") ]) }
  end

  test "version two interpretation creates separate immutable evidence with identical source and content identity" do
    raw = fixture("brighton_shortened_accumulation")
    at = Time.iso8601(raw.fetch("_fixture").fetch("evaluation_at"))
    current = normalized(raw)
    legacy = current.deep_dup
    legacy["normalization_version"] = 1
    %w[snowfallAmount quantitativePrecipitation].each do |name|
      legacy["quality"]["layers"][name]["diagnostics"] = [ "uncertain_accumulation_duration" ]
    end
    old = record(legacy, at: at)[:observation]
    original = old.attributes.deep_dup
    assert_equal "unknown", old.quality["state"]
    fresh = record(current, at: at)
    assert_equal "created", fresh[:disposition]
    assert_equal 2, fresh[:observation].normalization_version
    assert_equal "complete", fresh[:observation].quality["state"]
    assert_equal old.source_updated_at, fresh[:observation].source_updated_at
    assert_equal old.content_sha256, fresh[:observation].content_sha256
    assert_equal old.selected_intervals, fresh[:observation].selected_intervals
    again = record(current, at: at + 1.hour)
    assert_equal "existing", again[:disposition]
    assert_equal fresh[:observation].id, again[:observation].id
    assert_equal 2, WeatherForecastObservation.where(resort: @resort).count
    assert_equal original, old.reload.attributes
    assert_raises(ActiveRecord::ReadOnlyRecord) { old.update!(normalization_version: 2) }
  end
end
