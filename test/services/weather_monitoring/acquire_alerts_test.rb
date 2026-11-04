require "test_helper"
require_relative "../../helpers/weather_monitoring_data"

class WeatherAcquireAlertsTest < ActiveSupport::TestCase
  include WeatherMonitoringData
  self.use_transactional_tests = false

  setup do
    travel_to ANCHOR
    @resort = pilot_resort
    @monitor = ResortWeatherMonitor.create!(resort: @resort, enabled: true, next_check_at: ANCHOR + 72.hours, next_probe_at: ANCHOR + 12.hours)
    @state = WeatherAlertAcquisition.create!(scope_key: WeatherAlertAcquisition::PILOT_SCOPE,
      query: { type: "point", latitude: @resort.latitude, longitude: @resort.longitude }, enabled: true)
    @query = @state.query
    @observations_before = WeatherAlertObservation.pluck(:id)
    HTTParty.stubs(:get).raises("Unexpected live NOAA request")
    Noaa::Alerts::Fetch.stubs(:call).returns(success("features" => []))
  end

  teardown do
    travel_back
    ids = WeatherAlertObservation.where.not(id: @observations_before).pluck(:id)
    signals = WeatherAlertSignal.where(weather_alert_observation_id: ids).pluck(:id)
    WeatherAlertSignalResort.where(weather_alert_signal_id: signals).delete_all
    WeatherAlertSignal.where(id: signals).delete_all
    WeatherAlertObservation.where(id: ids).delete_all
    WeatherAlertAcquisition.where(id: @state.id).delete_all
    ResortWeatherMonitor.where(id: @monitor.id).delete_all
    Resort.where(id: @resort.id).delete_all
  end

  def success(value)
    ServiceResult.new(success: true, value: value)
  end

  def acquire
    WeatherMonitoring::AcquireAlerts.call(acquisition: WeatherAlertAcquisition.find(@state.id))
  end

  def failed_point_cancellation
    body = fixture("brighton_alert_signal")
    body["features"][0]["properties"].merge!("messageType" => "Cancel", "references" => [ { "identifier" => "urn:oid:previous" } ],
      "affectedZones" => [], "geocode" => {})
    Noaa::Alerts::Fetch.stubs(:call).returns(success(body))
    WeatherMonitoring::GenerateAlertSignals.expects(:call).returns(ServiceResult.new(success: false, value: { code: "alert_signal_persistence_error" }))
    assert acquire.failure?
    WeatherMonitoring::GenerateAlertSignals.unstub(:call)
    @state.reload.pending_evidence.deep_dup
  end

  test "verified empty success advances bounded watermark and cadence without touching forecast" do
    before = @monitor.attributes
    Noaa::Alerts::Fetch.expects(:call).with do |**options|
      refute WeatherAlertAcquisition.connection_pool.with_connection(&:transaction_open?)
      assert_equal({ latitude: @resort.latitude, longitude: @resort.longitude, active: false,
        since: ANCHOR - 24.hours, through: ANCHOR }, options)
      true
    end.returns(success("features" => []))
    result = acquire
    assert result.success?, result.value.inspect
    assert_equal ANCHOR, @state.reload.covered_through_at
    assert_equal ANCHOR - 24.hours, @state.covered_from_at
    assert_equal ANCHOR, @state.last_success_at
    assert_equal ANCHOR, @state.last_attempt_at
    assert_equal ANCHOR + 10.minutes, @state.next_check_at
    assert_nil @state.lease_token
    assert_nil @state.lease_expires_at
    assert_equal before, @monitor.reload.attributes
    assert_equal 0, WeatherAlertSignal.count
    Noaa::Alerts::Fetch.expects(:call).never
    assert_equal "not_due", acquire.value[:reason]
  end

  test "explicit cancellation and repeated windows reuse observations and signals" do
    collection = fixture("brighton_alert_signal")
    collection["features"][0]["properties"].merge!("messageType" => "Cancel", "references" => [ { "identifier" => "urn:oid:previous" } ])
    Noaa::Alerts::Fetch.stubs(:call).returns(success(collection))
    assert acquire.success?
    assert_equal "cancelled", WeatherAlertSignal.first.signal_type
    travel_to ANCHOR + 10.minutes
    assert_no_difference [ "WeatherAlertObservation.count", "WeatherAlertSignal.count", "WeatherAlertSignalResort.count" ] do
      assert acquire.success?
    end
    assert_equal ANCHOR + 10.minutes, @state.reload.covered_through_at
  end

  test "transport and partial pagination failures preserve successful truth and back off" do
    assert acquire.success?
    watermark, succeeded = @state.reload.attributes.values_at("covered_through_at", "last_success_at")
    [ "transport_error", "alert_pagination_invalid" ].each_with_index do |code, index|
      at = ANCHOR + (index + 1).hours
      travel_to at
      Noaa::Alerts::Fetch.stubs(:call).returns(ServiceResult.new(success: false, value: { code: code }))
      result = acquire
      assert result.failure?
      assert_equal code, result.value[:code]
      assert_equal watermark, @state.reload.covered_through_at
      assert_equal succeeded, @state.last_success_at
      assert_equal index + 1, @state.consecutive_failures
      assert_equal at + (index.zero? ? 10.minutes : 20.minutes), @state.next_check_at
      assert_nil @state.lease_token
    end
  end

  test "429 retry deadline is durable and never bypassed by heartbeats" do
    Noaa::Alerts::Fetch.expects(:call).once.returns(ServiceResult.new(success: false, value: { code: "rate_limited", retry_at: ANCHOR + 2.hours }))
    assert acquire.failure?
    assert_equal ANCHOR + 2.hours, @state.reload.next_check_at
    assert_equal "not_due", acquire.value[:reason]
    travel_to ANCHOR + 2.hours
    Noaa::Alerts::Fetch.stubs(:call).returns(success("features" => []))
    assert acquire.success?
    assert_equal 0, @state.reload.consecutive_failures
    assert_nil @state.last_error_code
  end

  test "signal failure retains source evidence and retry is idempotent" do
    Noaa::Alerts::Fetch.stubs(:call).returns(success(fixture("brighton_alert_signal")))
    WeatherMonitoring::GenerateAlertSignals.expects(:call).returns(ServiceResult.new(success: false, value: { code: "alert_signal_persistence_error" }))
    assert acquire.failure?
    assert_equal 1, WeatherAlertObservation.count
    assert_equal 0, WeatherAlertSignal.count
    assert_nil @state.reload.covered_through_at
    WeatherMonitoring::GenerateAlertSignals.unstub(:call)
    travel_to ANCHOR + 10.minutes
    assert_no_difference "WeatherAlertObservation.count" do
      assert acquire.success?
    end
    assert_equal 1, WeatherAlertSignal.count
  end

  test "initial failed evidence is replayed after sixty hours even when NOAA returns nothing" do
    body = fixture("brighton_alert_signal")
    body["features"][0]["properties"].merge!("messageType" => "Cancel", "references" => [ { "identifier" => "urn:oid:previous" } ],
      "affectedZones" => [], "geocode" => {})
    Noaa::Alerts::Fetch.stubs(:call).returns(success(body))
    WeatherMonitoring::GenerateAlertSignals.expects(:call).returns(ServiceResult.new(success: false, value: { code: "alert_signal_persistence_error" }))
    assert acquire.failure?
    source = WeatherAlertObservation.first
    original = source.attributes
    assert_nil @state.reload.covered_through_at
    WeatherMonitoring::GenerateAlertSignals.unstub(:call)
    travel_to ANCHOR + 60.hours
    Noaa::Alerts::Fetch.stubs(:call).returns(success("features" => []))
    result = acquire
    assert result.success?, result.value.inspect
    assert_equal 1, WeatherAlertSignal.count, "persisted cancellation must not be stranded outside the rolling window"
    assert_equal source.id, WeatherAlertSignal.first.weather_alert_observation_id
    assert_equal "cancelled", WeatherAlertSignal.first.signal_type
    assert_equal original, source.reload.attributes
    assert_equal ANCHOR + 60.hours, @state.reload.covered_through_at
    assert_equal ANCHOR - 24.hours, @state.covered_from_at
    assert_empty @state.coverage_gaps
    assert_nil @state.pending_evidence
    assert_equal 1, @state.last_result["replayed_created_count"]
    provenance = WeatherAlertSignalResort.first.evidence
    assert_equal "noaa_point_query", provenance["method"]
    assert_equal ANCHOR.iso8601, provenance["queried_at"]
    assert_equal (ANCHOR - 24.hours).iso8601, provenance["since_at"]
    assert_equal ANCHOR.iso8601, provenance["through_at"]
  end

  test "pending source evidence blocks coverage when replay fails again" do
    pending = failed_point_cancellation
    travel_to ANCHOR + 60.hours
    Noaa::Alerts::Fetch.expects(:call).never
    WeatherMonitoring::GenerateAlertSignals.expects(:call).returns(ServiceResult.new(success: false, value: { code: "alert_signal_persistence_error" }))
    assert acquire.failure?
    assert_nil @state.reload.covered_through_at
    assert_nil @state.last_success_at
    assert_equal pending, @state.pending_evidence
    assert_equal 0, WeatherAlertSignal.count
  end

  test "missing receipt provenance fails closed without fabricating a point association" do
    receipt = failed_point_cancellation
    [ "query", "recorded_at", "from", "through" ].each do |missing|
      travel_to ANCHOR + 60.hours
      @state.reload.update!(pending_evidence: receipt.except(missing), next_check_at: ANCHOR)
      Noaa::Alerts::Fetch.expects(:call).never
      result = acquire
      assert result.failure?
      assert_equal "invalid_pending_alert_evidence", result.value[:code]
      assert_nil @state.reload.covered_through_at
      assert_equal receipt.except(missing), @state.pending_evidence
    end
    assert_equal 0, WeatherAlertSignal.count
  end

  test "disable and reenable before first success retain the original window and pending evidence" do
    receipt = failed_point_cancellation
    @state.reload.update!(enabled: false)
    travel_to ANCHOR + 60.hours
    Noaa::Alerts::Fetch.expects(:call).never
    assert_equal "disabled", acquire.value[:reason]
    assert_equal receipt, @state.reload.pending_evidence
    assert_equal ANCHOR - 24.hours, @state.initial_window_start_at
    Noaa::Alerts::Fetch.unstub(:call)
    @state.update!(enabled: true)
    Noaa::Alerts::Fetch.expects(:call).once.with(has_entries(since: ANCHOR - 24.hours)).returns(success("features" => []))
    assert acquire.success?
    assert_equal 1, WeatherAlertSignal.count
    assert_nil @state.reload.pending_evidence
    assert_empty @state.coverage_gaps
  end

  test "persisted evidence outlives provider recovery horizon while unknown coverage remains a gap" do
    failed_point_cancellation
    travel_to ANCHOR + 8.days
    Noaa::Alerts::Fetch.expects(:call).with(has_entries(since: ANCHOR + 2.days)).returns(success("features" => []))
    result = acquire
    assert result.success?, result.value.inspect
    assert_equal 1, WeatherAlertSignal.count
    assert_equal "cancelled", WeatherAlertSignal.first.signal_type
    assert_equal [ { "from" => (ANCHOR - 24.hours).iso8601, "through" => (ANCHOR + 2.days).iso8601 } ], @state.reload.coverage_gaps
    assert result.value[:coverage_uncertain]
    assert_nil @state.pending_evidence
  end

  test "termination after checkpoint leaves source receipt recoverable across lease expiry" do
    body = fixture("brighton_alert_signal")
    body["features"][0]["properties"].merge!("messageType" => "Cancel", "references" => [ { "identifier" => "urn:oid:previous" } ])
    Noaa::Alerts::Fetch.stubs(:call).returns(success(body))
    WeatherMonitoring::ReplayAlertEvidence.expects(:call).raises(Interrupt)
    assert_raises(Interrupt) { acquire }
    assert_equal 1, WeatherAlertObservation.count
    assert @state.reload.pending_evidence
    assert_nil @state.covered_through_at
    WeatherMonitoring::ReplayAlertEvidence.unstub(:call)
    travel_to ANCHOR + 60.hours
    Noaa::Alerts::Fetch.stubs(:call).returns(success("features" => []))
    assert acquire.success?
    assert_equal 1, WeatherAlertSignal.count
    assert_nil @state.reload.pending_evidence
  end

  test "source rows and pending receipt roll back together if checkpoint is interrupted" do
    Noaa::Alerts::Fetch.stubs(:call).returns(success(fixture("brighton_alert_signal")))
    original = WeatherMonitoring::CheckpointAlertEvidence.method(:call)
    interrupted = lambda do |**inputs|
      save = inputs[:acquisition].method(:save!)
      inputs[:acquisition].define_singleton_method(:save!) do |*args, **kwargs|
        save.call(*args, **kwargs)
        raise Interrupt
      end
      original.call(**inputs)
    end
    WeatherMonitoring::CheckpointAlertEvidence.stub(:call, interrupted) do
      assert_raises(Interrupt) { acquire }
    end
    assert_equal 0, WeatherAlertObservation.count
    assert_nil @state.reload.pending_evidence
    assert_nil @state.covered_through_at
    assert @state.lease_token
  end

  test "concurrent retry replays one durable receipt without duplicate signals" do
    failed_point_cancellation
    travel_to ANCHOR + 60.hours
    ready, release, results = Queue.new, Queue.new, Queue.new
    original = WeatherMonitoring::GenerateAlertSignals.method(:call)
    first_call = true
    worker = nil
    generate = lambda do |**inputs|
      if first_call
        first_call = false
        ready << true
        release.pop
      end
      original.call(**inputs)
    end
    Noaa::Alerts::Fetch.expects(:call).once.returns(success("features" => []))
    WeatherMonitoring::GenerateAlertSignals.stub(:call, generate) do
      worker = Thread.new do
        results << acquire
      rescue StandardError => error
        results << error
      end
      Timeout.timeout(10) { ready.pop }
      assert_equal "leased", acquire.value[:reason]
      release << true
      result = Timeout.timeout(10) { results.pop }
      raise result if result.is_a?(Exception)

      assert result.success?, result.value.inspect
      worker.join
    end
    assert_equal 1, WeatherAlertSignal.count
    assert_equal 1, WeatherAlertSignalResort.count
    assert_nil @state.reload.pending_evidence
  ensure
    release << true if release
    worker&.join(10)
  end

  test "pre remediation unfinished attempts require review instead of invented provenance" do
    @state.update!(last_attempt_at: ANCHOR - 60.hours, consecutive_failures: 1)
    Noaa::Alerts::Fetch.expects(:call).never
    result = acquire
    assert result.failure?
    assert_equal "legacy_unfinished_alert_acquisition", result.value[:code]
    assert_nil @state.reload.initial_window_start_at
    assert_nil @state.covered_through_at
  end

  test "clean existing successful acquisition can retain its watermark across migration" do
    @state.update!(last_attempt_at: ANCHOR - 1.hour, last_success_at: ANCHOR - 59.minutes, covered_through_at: ANCHOR - 1.hour)
    assert acquire.success?
    assert_equal ANCHOR, @state.reload.covered_through_at
    assert @state.initial_window_start_at
  end

  test "failed recorder cannot commit source rows without the durable receipt" do
    Noaa::Alerts::Fetch.stubs(:call).returns(success(fixture("brighton_alert_signal")))
    original = WeatherMonitoring::RecordAlertObservations.method(:call)
    partial_failure = lambda do |**inputs|
      original.call(**inputs)
      ServiceResult.new(success: false, value: { code: "invalid_alert_evidence" })
    end
    WeatherMonitoring::RecordAlertObservations.stub(:call, partial_failure) do
      assert acquire.failure?
    end
    assert_equal 0, WeatherAlertObservation.count
    assert_nil @state.reload.pending_evidence
    assert_nil @state.covered_through_at
  end

  test "stale worker cannot checkpoint over a newer owner's pending evidence" do
    old = WeatherMonitoring::ClaimAlertAcquisition.call(acquisition: @state).value
    travel_to ANCHOR + 5.minutes
    replacement = WeatherMonitoring::ClaimAlertAcquisition.call(acquisition: @state).value
    result = WeatherMonitoring::CheckpointAlertEvidence.call(acquisition: @state, claim: replacement, collection: fixture("brighton_alert_signal"))
    assert result.success?, result.value.inspect
    pending = @state.reload.pending_evidence.deep_dup
    before = @state.attributes
    assert_no_difference "WeatherAlertObservation.count" do
      stale = WeatherMonitoring::CheckpointAlertEvidence.call(acquisition: @state, claim: old, collection: fixture("brighton_alert_signal"))
      assert stale.failure?
      assert_equal "alert_acquisition_superseded", stale.value[:code]
    end
    assert_equal pending, @state.reload.pending_evidence
    assert_equal before, @state.attributes
  end

  test "late appearing source is captured by rolling replay despite newer watermark" do
    assert acquire.success?
    travel_to ANCHOR + 10.minutes
    Noaa::Alerts::Fetch.expects(:call).with(has_entries(since: ANCHOR + 10.minutes - 24.hours, through: ANCHOR + 10.minutes))
      .returns(success(fixture("brighton_alert_signal")))
    assert acquire.success?
    assert_equal 1, WeatherAlertSignal.count
    assert_operator WeatherAlertObservation.first.source_sent_at, :<, ANCHOR
  end

  test "short outage recovers from watermark and longer outage persists unrecoverable gap" do
    @state.update!(covered_through_at: ANCHOR - 36.hours)
    Noaa::Alerts::Fetch.expects(:call).with(has_entries(since: ANCHOR - 36.hours - 30.minutes)).returns(success("features" => []))
    assert acquire.success?
    assert_empty @state.reload.coverage_gaps
    @state.update!(covered_through_at: ANCHOR - 8.days, next_check_at: ANCHOR)
    result = acquire
    assert result.success?
    assert_equal "recovery_gap", result.value[:coverage_status]
    gap = { "from" => (ANCHOR - 8.days).iso8601, "through" => (ANCHOR - 6.days).iso8601 }
    assert_equal [ gap ], @state.reload.coverage_gaps
    travel_to ANCHOR + 10.minutes
    assert acquire.success?
    assert_equal [ gap ], @state.reload.coverage_gaps, "later success must not erase uncertainty"
  end

  test "crashed process lease expires and old worker cannot overwrite new success" do
    first = WeatherMonitoring::ClaimAlertAcquisition.call(acquisition: @state)
    assert first.success?
    assert_equal "claimed", first.value[:disposition]
    assert_equal "leased", acquire.value[:reason]
    travel_to ANCHOR + 5.minutes
    assert acquire.success?
    before = @state.reload.attributes
    old = WeatherMonitoring::CompleteAlertAcquisition.call(acquisition: @state, claim: first.value,
      result: success(created_count: 0))
    assert old.failure?
    assert_equal "alert_acquisition_superseded", old.value[:code]
    assert_equal before, @state.reload.attributes
    old_failure = WeatherMonitoring::CompleteAlertAcquisition.call(acquisition: @state, claim: first.value,
      result: ServiceResult.new(success: false, value: { code: "transport_error" }))
    assert old_failure.failure?
    assert_equal before, @state.reload.attributes
  end

  test "lease expired without takeover cannot advance watermark" do
    claim = WeatherMonitoring::ClaimAlertAcquisition.call(acquisition: @state).value
    travel_to ANCHOR + 5.minutes
    result = WeatherMonitoring::CompleteAlertAcquisition.call(acquisition: @state, claim: claim, result: success(created_count: 0))
    assert result.failure?
    assert_nil @state.reload.covered_through_at
  end

  test "concurrent runners make one source request and release durable claim" do
    ready, release, results = Queue.new, Queue.new, Queue.new
    worker = nil
    fetch = lambda do |**_options|
      ready << true
      release.pop
      success("features" => [])
    end
    Noaa::Alerts::Fetch.unstub(:call)
    Noaa::Alerts::Fetch.stub(:call, fetch) do
      worker = Thread.new do
        results << acquire
      rescue StandardError => error
        results << error
      end
      Timeout.timeout(10) { ready.pop }
      other = acquire
      assert other.success?
      assert_equal "leased", other.value[:reason]
      assert_equal "leased", other.value[:decision][:reason]
      assert_equal "skipped", other.value[:decision][:disposition]
      assert_equal @state.id, other.value[:decision][:acquisition_id]
      assert_equal false, other.value[:decision][:pending_evidence]
      release << true
      first = Timeout.timeout(10) { results.pop }
      raise first if first.is_a?(Exception)

      assert first.success?, first.value.inspect
      assert_equal "claimed", first.value[:decision][:disposition]
      assert_equal "acquisition_due", first.value[:decision][:reason]
      worker.join
    end
    assert_nil @state.reload.lease_token
    assert_equal ANCHOR, @state.covered_through_at
  ensure
    release << true if release
    worker&.join(10)
  end

  test "disabled acquisition is skipped but source acquisition is not owned by forecast monitor" do
    @state.update!(enabled: false)
    Noaa::Alerts::Fetch.expects(:call).never
    assert_equal "disabled", acquire.value[:reason]
    Noaa::Alerts::Fetch.unstub(:call)
    @state.update!(enabled: true)
    @monitor.update!(enabled: false)
    Noaa::Alerts::Fetch.expects(:call).returns(success(fixture("brighton_alert_signal")))
    assert acquire.success?
    assert_equal 1, WeatherAlertObservation.count
    assert_equal 0, WeatherAlertSignal.count, "consumer eligibility is enforced separately"
  end

  test "unapproved geographic scope cannot trigger requests" do
    Noaa::Alerts::Fetch.expects(:call).never
    @state.update_columns(scope_key: "other_region")
    assert_equal "pilot_scope_only", acquire.value[:reason]
    @state.update_columns(scope_key: WeatherAlertAcquisition::PILOT_SCOPE, query: @query.merge("latitude" => 0))
    assert_equal "unapproved_acquisition_geography", acquire.value[:code]
  end

  test "unexpected processing error is visible and does not advance coverage" do
    WeatherMonitoring::ProcessAlertCollection.expects(:call).raises(ArgumentError, "test programming bug")
    Rails.error.expects(:report).with(instance_of(ArgumentError), handled: true)
    result = acquire
    assert result.failure?
    assert_equal "unexpected_alert_acquisition_error", result.value[:code]
    assert_nil @state.reload.covered_through_at
    assert_equal 1, @state.consecutive_failures
  end

  test "recovery failure records uncertainty without claiming successful gap recovery" do
    previous = ANCHOR - 8.days
    @state.update!(covered_through_at: previous)
    Noaa::Alerts::Fetch.stubs(:call).returns(ServiceResult.new(success: false, value: { code: "transport_error" }))
    result = acquire
    assert result.failure?
    assert result.value[:coverage_uncertain]
    assert_equal previous, @state.reload.covered_through_at
    assert_empty @state.coverage_gaps, "unconfirmed recovery must not be stored as successful coverage"
    assert_equal false, @state.last_result["window_processed"]
    assert_equal previous.iso8601, @state.last_result.dig("coverage_gap", "from")
  end

  test "disable and version changes fence completion even without another lease owner" do
    claim = WeatherMonitoring::ClaimAlertAcquisition.call(acquisition: @state).value
    @state.reload.update!(enabled: false)
    @state.update!(enabled: true)
    before = @state.reload.attributes
    result = WeatherMonitoring::CompleteAlertAcquisition.call(acquisition: @state, claim: claim, result: success(created_count: 0))
    assert result.failure?
    assert_equal before, @state.reload.attributes
  end

  test "completion database error rolls back without losing immutable evidence" do
    Noaa::Alerts::Fetch.stubs(:call).returns(success(fixture("brighton_alert_signal")))
    finish = WeatherMonitoring::CompleteAlertAcquisition.method(:call)
    injected = lambda do |**inputs|
      inputs[:acquisition].define_singleton_method(:save!) { raise ActiveRecord::StatementInvalid, "test completion DB failure" }
      finish.call(**inputs)
    end
    WeatherMonitoring::CompleteAlertAcquisition.stub(:call, injected) do
      result = acquire
      assert result.failure?
      assert_equal "alert_acquisition_persistence_error", result.value[:code]
    end
    assert_nil @state.reload.covered_through_at
    assert_nil @state.last_success_at
    assert_equal 1, WeatherAlertObservation.count
    assert_equal 1, WeatherAlertSignal.count
    assert @state.lease_token, "a crashed/failed completion is recovered by lease expiry"
  end

  test "an enclosing transaction is refused before any network call" do
    Noaa::Alerts::Fetch.expects(:call).never
    before = @state.attributes
    WeatherAlertAcquisition.transaction do
      result = acquire
      assert result.failure?
      assert_equal "acquisition_transaction_open", result.value[:code]
    end
    assert_equal before, @state.reload.attributes
  end
end
