require "test_helper"
require_relative "../../helpers/weather_monitoring_data"

class WeatherRecordAlertsTest < ActiveSupport::TestCase
  include WeatherMonitoringData

  def record(collection = fixture("ut_winter_alert_updates"), persist: true)
    result = WeatherMonitoring::RecordAlertObservations.call(collection: collection, zone_ids: [ "UTZ111" ], seen_at: ANCHOR, persist: persist)
    assert result.success?, result.value.inspect
    result.value
  end

  test "relevant evidence is deduplicated with update references and no resort copies" do
    result = record
    assert_equal 2, result[:records].size
    assert_equal 2, result[:changed].size
    assert_empty result[:active_identifiers]
    assert result[:records].all? { |row| row.event == "Winter Weather Advisory" }
    assert result[:records].all? { |row| row.evidence["references"].any? }
    assert result[:records].any? { |row| row.evidence["replacedBy"].present? }
    assert_empty record[:changed]
    assert_equal 2, WeatherAlertObservation.count
    assert_raises(ActiveRecord::ReadOnlyRecord) { result[:records].first.update!(event: "changed") }
  end

  test "test exercise and unrelated zones never qualify" do
    collection = fixture("ut_winter_alert_updates")
    collection["features"].each { |feature| feature["properties"]["status"] = "Test" }
    assert_empty record(collection)[:records]
    collection["features"].each { |feature| feature["properties"]["status"] = "Exercise" }
    assert_empty record(collection)[:records]
  end

  test "dry run writes nothing and same ID changed evidence creates a revision" do
    assert_empty record(persist: false)[:records]
    assert_equal 0, WeatherAlertObservation.count
    record
    collection = fixture("ut_winter_alert_updates")
    collection["features"].each { |feature| feature["properties"]["headline"] = "Revised" }
    assert_equal 2, record(collection)[:changed].size
    assert_equal 4, WeatherAlertObservation.count
  end

  test "cancel is evidence not snowfall and removal alone is not cancellation" do
    feature = fixture("ut_winter_alert_updates")["features"].find { |f| f["properties"].dig("geocode", "UGC") == [ "UTZ111" ] }
    feature["properties"]["messageType"] = "Cancel"
    feature["properties"]["sent"] = ANCHOR.iso8601
    result = record({ "features" => [ feature ] })
    assert_equal 1, result[:changed].size
    assert_empty result[:active_identifiers]
    record({ "features" => [] })
    assert_equal 1, WeatherAlertObservation.count
  end
  test "malformed eligible message fails without partially recording collection" do
    collection = fixture("ut_winter_alert_updates")
    collection["features"].find { |feature| feature["properties"]["event"] == "Winter Weather Advisory" }["properties"].delete("id")
    result = WeatherMonitoring::RecordAlertObservations.call(collection: collection, zone_ids: [ "UTZ111" ], seen_at: ANCHOR)
    assert result.failure?
    assert_equal 0, WeatherAlertObservation.count
  end
end
