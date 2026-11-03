require "test_helper"
require_relative "../../helpers/weather_monitoring_data"

class WeatherGenerateAlertSignalsTest < ActiveSupport::TestCase
  include WeatherMonitoringData

  setup do
    @resort = pilot_resort
    @mapping = fixture("brighton_points")["properties"].merge("latitude" => @resort.latitude, "longitude" => @resort.longitude)
    @monitor = ResortWeatherMonitor.create!(resort: @resort, enabled: true, mapping: @mapping)
    HTTParty.stubs(:get).raises("Unexpected live NOAA request")
  end

  def observation(changes = {}, at: ANCHOR, geometry: nil, **fields)
    changes = changes.merge(fields)
    collection = fixture("brighton_alert_signal")
    collection["features"][0]["properties"].merge!(changes)
    collection["features"][0]["geometry"] = geometry
    result = WeatherMonitoring::RecordAlertObservations.call(collection: collection, zone_ids: [], seen_at: at, signal_evidence: true)
    assert result.success?, result.value.inspect
    result.value[:records].first
  end

  def generate(*records, **options)
    WeatherMonitoring::GenerateAlertSignals.call(observations: records, detected_at: ANCHOR, **options)
  end

  def reference(record)
    [ { "identifier" => record.source_identifier, "sent" => record.source_sent_at.iso8601, "sender" => "w-nws.webmaster@noaa.gov" } ]
  end

  test "new native alert creates immutable signal with source and local times and geography" do
    record = observation
    before = record.attributes
    result = generate(record)
    assert result.success?, result.value.inspect
    assert_equal 1, result.value[:created_count]
    outcome = result.value[:outcomes].first
    assert_equal record.source_identifier, outcome[:source_identifier]
    assert_equal record.source_sent_at, outcome[:source_sent_at]
    assert_equal ANCHOR, outcome[:detected_at]
    assert_equal "High Wind Warning", outcome[:event]
    assert_equal [], outcome[:changed_fields]
    signal = WeatherAlertSignal.first
    assert_equal record.id, signal.weather_alert_observation_id
    assert_equal "issued", signal.signal_type
    assert_equal "High Wind Warning", signal.weather_alert_observation.event
    assert_equal Time.iso8601("2026-10-20T15:00:00Z"), signal.weather_alert_observation.source_sent_at
    assert_equal ANCHOR, signal.detected_at
    assert_equal [ @resort.id ], signal.resorts.pluck(:id)
    assert_equal [ "UTZ111" ], signal.weather_alert_signal_resorts.first.evidence["zone_ids"]
    assert_equal before, record.reload.attributes
    assert_raises(ActiveRecord::ReadOnlyRecord) { signal.update!(signal_type: "cancelled") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { signal.weather_alert_signal_resorts.first.destroy! }
  end

  test "identical retrieval and repeated processing create no duplicate evidence signals or associations" do
    record = observation
    assert generate(record).success?
    before = WeatherAlertSignal.first.attributes
    assert_no_difference [ "WeatherAlertObservation.count", "WeatherAlertSignal.count", "WeatherAlertSignalResort.count" ] do
      same = observation
      assert_equal record.id, same.id
      result = generate(same)
      assert result.success?, result.value.inspect
      assert_equal "existing", result.value[:outcomes].first[:disposition]
    end
    assert_equal before, WeatherAlertSignal.first.attributes
  end

  test "same message changed description instruction severity or areas records meaningful revisions" do
    first = observation
    assert generate(first).success?
    [ { "description" => "Winds increasing materially." }, { "instruction" => "Stay indoors." },
      { "severity" => "Extreme" }, { "affectedZones" => [ "https://api.weather.gov/zones/county/UTC035" ], "geocode" => { "UGC" => [ "UTC035" ] } } ].each_with_index do |fields, index|
      changed = observation(fields, at: ANCHOR + (index + 1).minutes)
      result = generate(changed)
      assert result.success?, result.value.inspect
      assert_equal "material_content_changed", result.value[:outcomes].first[:signal_type]
      assert WeatherAlertSignal.find_by!(weather_alert_observation: changed).change_details["fields"].any?
    end
    assert_equal 5, WeatherAlertObservation.count
    assert_equal 5, WeatherAlertSignal.count
    assert_equal "Strong winds expected across the mountains.", first.reload.evidence["description"]
  end

  test "native update with a different identifier links references without inventing a storm identity" do
    first = observation
    assert generate(first).success?
    changed = observation("id" => "urn:oid:update-2", "sent" => (ANCHOR + 1.minute).iso8601,
      "messageType" => "Update", "references" => reference(first), "description" => "Wind speeds increased.")
    assert generate(changed).success?
    signal = WeatherAlertSignal.find_by!(weather_alert_observation: changed)
    assert_equal "updated", signal.signal_type
    assert_equal first.id, signal.previous_observation_id
    assert_equal [ first.source_identifier ], signal.change_details["reference_identifiers"]
  end

  test "new revision with only references replacement metadata or source sent change is not a new signal" do
    first = observation
    assert generate(first).success?
    changed = observation({ "references" => reference(first), "note" => "API metadata changed" }, at: ANCHOR + 1.minute)
    result = generate(changed)
    assert_equal "metadata_only_change", result.value[:outcomes].first[:reason]
    revised = observation({ "replacedAt" => ANCHOR.iso8601 }, at: ANCHOR + 2.minutes)
    assert_equal "metadata_only_change", generate(revised).value[:outcomes].first[:reason]
    assert_equal 3, WeatherAlertObservation.count
    assert_equal 1, WeatherAlertSignal.count
  end

  test "explicit cancellation is distinct from expiration and absence" do
    first = observation
    assert generate(first).success?
    cancelled = observation("id" => "urn:oid:cancel", "messageType" => "Cancel", "references" => reference(first),
      "expires" => (ANCHOR - 1.minute).iso8601)
    assert_equal "cancelled", generate(cancelled).value[:outcomes].first[:signal_type]
    expired = observation("id" => "urn:oid:expired", "expires" => (ANCHOR - 1.minute).iso8601)
    assert_equal "expired_evidence", generate(expired).value[:outcomes].first[:reason]
    assert_equal 1, WeatherAlertSignal.where(signal_type: "cancelled").count
    assert_no_difference "WeatherAlertSignal.count" do
      assert generate.success?
    end
  end

  test "only unambiguous explicit VTEC correction is classified corrected" do
    first = observation
    correction = observation("id" => "urn:oid:corrected", "messageType" => "Update", "references" => reference(first),
      "description" => "Corrected wind speeds.", "parameters" => { "VTEC" => [ "/O.COR.KSLC.HW.W.0001.261020T1800Z-261021T1700Z/" ] })
    assert_equal "corrected", generate(correction).value[:outcomes].first[:signal_type]
    mixed = observation("id" => "urn:oid:mixed", "messageType" => "Update", "references" => reference(first),
      "description" => "One segment ends; another continues.", "parameters" => { "VTEC" => [ "/O.CAN.KSLC.HW.W.0001.261020T1800Z-261021T1700Z/", "/O.CON.KSLC.HW.W.0002.261020T1800Z-261021T1700Z/" ] })
    assert_equal "updated", generate(mixed).value[:outcomes].first[:signal_type]
    exp = observation("id" => "urn:oid:exp", "messageType" => "Update", "references" => reference(first),
      "parameters" => { "VTEC" => [ "/O.EXP.KSLC.HW.W.0001.261020T1800Z-261021T1700Z/" ] })
    assert_equal "expired_evidence", generate(exp).value[:outcomes].first[:reason]
  end

  test "unknown lifecycle missing references and incomplete evidence are explicit skips" do
    unknown = observation("messageType" => "Ack")
    assert_equal "unknown_lifecycle", generate(unknown).value[:outcomes].first[:reason]
    update = observation("messageType" => "Update")
    assert_equal "missing_references", generate(update).value[:outcomes].first[:reason]
    legacy = WeatherMonitoring::RecordAlertObservations.call(collection: fixture("ut_winter_alert_updates"), zone_ids: [ "UTZ111" ], seen_at: ANCHOR).value[:records].first
    assert_equal "incomplete_evidence", generate(legacy).value[:outcomes].first[:reason]
    assert_equal 0, WeatherAlertSignal.count
  end

  test "unambiguous operational VTEC cancellation is supported without inventing cancellation from mixed segments" do
    first = observation
    ended = observation("id" => "urn:oid:vtec-cancel", "messageType" => "Update", "references" => reference(first),
      "parameters" => { "VTEC" => [ "/O.CAN.KSLC.HW.W.0001.261020T1800Z-261021T1700Z/" ] })
    assert_equal "cancelled", generate(ended).value[:outcomes].first[:signal_type]
    uncertain = observation("id" => "urn:oid:invalid-vtec", "messageType" => "Update", "references" => reference(first),
      "description" => "Revised wording.", "parameters" => { "VTEC" => [ "/O.COR.KSLC.HW.W.0001.261020T1800Z-261021T1700Z/", "unparseable segment" ] })
    assert_equal "updated", generate(uncertain).value[:outcomes].first[:signal_type]
  end

  test "first seen update with missing baseline is updated rather than invented issuance" do
    updated = observation("messageType" => "Update", "references" => [ { "identifier" => "urn:oid:not-observed" } ])
    result = generate(updated)
    assert_equal "updated", result.value[:outcomes].first[:signal_type]
    signal = WeatherAlertSignal.first
    assert_nil signal.previous_observation_id
    assert_equal "unavailable", signal.change_details["baseline"]
  end

  test "unrelated metadata and affected-zone ordering do not create delivery candidates" do
    zones = [ "https://api.weather.gov/zones/forecast/UTZ111", "https://api.weather.gov/zones/county/UTC035" ]
    first = observation("affectedZones" => zones)
    assert generate(first).success?
    second = observation({ "affectedZones" => zones.reverse }, at: ANCHOR + 1.minute)
    assert_equal "metadata_only_change", generate(second).value[:outcomes].first[:reason]
    assert_equal 1, WeatherAlertSignal.count
  end

  test "county mapping is authoritative and unrelated or missing mapping never guesses relevance" do
    county = observation("affectedZones" => [ "https://api.weather.gov/zones/county/UTC035" ], "geocode" => { "UGC" => [ "UTC035" ] })
    assert_equal 1, generate(county).value[:created_count]
    unrelated = observation("id" => "urn:oid:unrelated", "affectedZones" => [], "geocode" => { "UGC" => [ "UTZ999" ] })
    assert_equal "no_approved_geographic_match", generate(unrelated).value[:outcomes].first[:reason]
    @monitor.update!(mapping: {})
    other = observation("id" => "urn:oid:missing-map")
    assert_equal "no_approved_geographic_match", generate(other).value[:outcomes].first[:reason]
  end

  test "verified point query supports polygon alerts without zone strings but requires matching coordinates" do
    record = observation({ "affectedZones" => [], "geocode" => {} }, geometry: { "type" => "Polygon", "coordinates" => [ [ [ -112, 40 ], [ -111, 40 ], [ -111, 41 ], [ -112, 40 ] ] ] })
    @monitor.update!(mapping: {})
    assert_equal 0, generate(record).value[:created_count]
    point = { @resort.id => { latitude: @resort.latitude, longitude: @resort.longitude, observation_ids: [ record.id ] } }
    assert_equal 1, generate(record, point_matches: point).value[:created_count]
    assert_equal "noaa_point_query", WeatherAlertSignalResort.first.evidence["method"]
    point[@resort.id][:latitude] = 0
    assert_equal "no_approved_geographic_match", generate(record, point_matches: point).value[:outcomes].first[:reason]
  end

  test "future multiple resort associations share one source revision and signal without enabling monitoring" do
    record = observation
    assert generate(record).success?
    other = Resort.create!(resort_name: "Future alert association", slug: "future-alert-association", latitude: 40, longitude: -111)
    signal = WeatherAlertSignal.first
    assert_no_difference [ "WeatherAlertSignal.count", "WeatherAlertObservation.count", "ResortWeatherMonitor.count" ] do
      WeatherAlertSignalResort.create!(weather_alert_signal: signal, resort: other, associated_at: ANCHOR,
        evidence: { "method" => "future_association_fixture" })
    end
    assert_equal 2, signal.resorts.count
    assert_equal 1, WeatherAlertObservation.count
    assert_equal 1, WeatherAlertSignal.count
  end

  test "inactive and nonpilot monitors do not confer geographic relevance" do
    record = observation
    @monitor.update!(enabled: false)
    assert_equal "no_approved_geographic_match", generate(record).value[:outcomes].first[:reason]
    assert_equal 0, WeatherAlertSignal.count
  end

  test "stale coordinate mapping and nonpilot relevance cannot generate signals" do
    record = observation
    @monitor.update!(mapping: @mapping.merge("latitude" => 0))
    assert_equal "no_approved_geographic_match", generate(record).value[:outcomes].first[:reason]
    other = Resort.create!(resort_name: "Nonpilot signal scope", slug: "nonpilot-signal-scope", latitude: 40, longitude: -111)
    ResortWeatherMonitor.create!(resort: other, enabled: true, mapping: @mapping.merge("latitude" => other.latitude, "longitude" => other.longitude))
    assert_equal "no_approved_geographic_match", generate(record, resorts: [ other ]).value[:outcomes].first[:reason]
    assert_equal 0, WeatherAlertSignal.count
  end

  test "test exercise or unsupported source evidence cannot generate signals" do
    record = observation
    %w[Test Exercise].each do |status|
      stored = WeatherAlertObservation.create!(record.attributes.except("id").merge("status" => status, "source_identifier" => "urn:oid:test-#{status}"))
      assert_equal "unsupported_source", generate(stored).value[:outcomes].first[:reason]
    end
    assert_equal 0, WeatherAlertSignal.count
  end

  test "an older same-message source revision cannot override newer evidence" do
    newer = observation("sent" => ANCHOR.iso8601)
    older = observation
    assert_equal "older_source_revision", generate(older).value[:outcomes].first[:reason]
    assert generate(newer).success?
    assert_equal 1, WeatherAlertSignal.count
  end

  test "rollback includes earlier signal writes in a failed batch" do
    first = observation
    second = observation("id" => "urn:oid:second-batch")
    original = WeatherAlertSignalResort.method(:create_or_find_by!)
    replacement = lambda do |**attributes, &block|
      if attributes[:weather_alert_signal].weather_alert_observation_id == second.id
        raise ActiveRecord::RecordInvalid.new(WeatherAlertSignalResort.new)
      end

      original.call(**attributes, &block)
    end
    WeatherAlertSignalResort.stub(:create_or_find_by!, replacement) do
      result = generate(first, second)
      assert result.failure?
      assert_equal "alert_signal_invalid", result.value[:code]
    end
    assert_equal 0, WeatherAlertSignal.count
    assert_equal 0, WeatherAlertSignalResort.count
    assert_equal 2, WeatherAlertObservation.count
  end

  test "missing or unsaved observation returns failure with no partial signals" do
    record = observation
    [ [ record, -1 ], [ WeatherAlertObservation.new ], nil ].each do |inputs|
      assert_no_difference "WeatherAlertSignal.count" do
        result = WeatherMonitoring::GenerateAlertSignals.call(observations: inputs)
        assert result.failure?
        assert_equal "alert_observation_missing", result.value[:code]
      end
    end
  end

  test "association validation failure rolls back signal and preserves source observation" do
    record = observation
    before = record.attributes
    WeatherAlertSignalResort.any_instance.expects(:save!).raises(ActiveRecord::RecordInvalid.new(WeatherAlertSignalResort.new))
    assert_no_difference [ "WeatherAlertSignal.count", "WeatherAlertSignalResort.count" ] do
      result = generate(record)
      assert result.failure?
      assert_equal "alert_signal_invalid", result.value[:code]
    end
    assert_equal before, record.reload.attributes
  end

  test "database failure rolls back and programming errors remain visible" do
    record = observation
    WeatherAlertSignal.expects(:create_or_find_by!).raises(ActiveRecord::StatementInvalid, "test DB failure")
    assert_equal "alert_signal_persistence_error", generate(record).value[:code]
    WeatherAlertSignal.expects(:create_or_find_by!).raises(ArgumentError, "test programming bug")
    assert_raises(ArgumentError) { generate(record) }
    assert_equal 0, WeatherAlertSignal.count
    assert_equal 0, WeatherAlertSignalResort.count
  end
end
