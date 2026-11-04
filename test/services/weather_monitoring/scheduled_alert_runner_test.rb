require "test_helper"
require_relative "../../helpers/weather_monitoring_data"

class WeatherScheduledAlertRunnerTest < ActiveSupport::TestCase
  include WeatherMonitoringData
  self.use_transactional_tests = false

  setup do
    travel_to ANCHOR
    @resort = pilot_resort
    @states = []
    HTTParty.stubs(:get).raises("Unexpected live NOAA request")
    Noaa::Alerts::Fetch.stubs(:call).returns(ServiceResult.new(success: true, value: { "features" => [] }))
  end

  teardown do
    WeatherAlertAcquisition.where(id: @states.map(&:id)).delete_all
    @resort.destroy!
    travel_back
  end

  def scope(**attributes)
    state = WeatherAlertAcquisition.create!({ scope_key: WeatherAlertAcquisition::PILOT_SCOPE, enabled: true,
      query: { type: "point", latitude: @resort.latitude, longitude: @resort.longitude } }.merge(attributes))
    @states << state
    state
  end

  def heartbeat
    WeatherMonitoring::ScheduledAlertRunner.call
  end

  def decision(result)
    result.value.fetch(:outcomes).first.fetch(:value).fetch(:decision)
  end

  test "zero configured scopes is a successful no op" do
    Noaa::Alerts::Fetch.expects(:call).never
    result = heartbeat
    assert result.success?
    [ :configured_count, :inspected_count, :candidate_count, :invoked_count, :successful_count, :skipped_count, :failed_count ].each do |key|
      assert_equal 0, result.value[key]
    end
    assert_empty result.value[:outcomes]
  end

  test "disabled outside pilot and future scopes are reported without HTTP" do
    scope(enabled: false)
    scope(scope_key: "other_region")
    scope(scope_key: "future_unapproved", next_check_at: ANCHOR + 1.hour)
    Noaa::Alerts::Fetch.expects(:call).never
    result = heartbeat
    assert result.success?
    assert_equal 3, result.value[:configured_count]
    assert_equal 3, result.value[:inspected_count]
    assert_equal 0, result.value[:candidate_count]
    assert_equal 0, result.value[:invoked_count]
    assert_equal 3, result.value[:skipped_count]
    assert_equal [ "disabled", "pilot_scope_only", "pilot_scope_only" ], result.value[:outcomes].map { |row| row[:value][:decision][:reason] }
  end

  test "scheduled recovery retains backoff priority and safe persisted metadata" do
    state = scope(next_check_at: ANCHOR + 1.hour, consecutive_failures: 2, last_error_code: "rate_limited",
      pending_evidence: { "private" => "receipt" })
    Noaa::Alerts::Fetch.expects(:call).never
    result = heartbeat
    value = decision(result)
    assert result.success?
    assert_equal "not_due", value[:reason]
    assert_equal "skipped", value[:disposition]
    assert_equal true, value[:pending_evidence]
    assert_equal ANCHOR, value[:decision_at]
    assert_equal state.next_check_at, value[:next_check_at]
    assert_equal 2, value[:consecutive_failures]
    assert_equal "rate_limited", value[:last_error_code]
    assert_equal 0, result.value[:candidate_count]
    assert_equal 1, result.value[:skipped_count]
    assert_equal 0, result.value[:failed_count]
    refute_includes result.to_h.to_json, "receipt"
    state.update!(pending_evidence: {})
    repeated = heartbeat
    assert_equal true, decision(repeated)[:pending_evidence]
    assert_equal "not_due", decision(repeated)[:reason]
    assert_equal 0, repeated.value[:invoked_count]
  end

  test "active owner takes precedence over future scheduling" do
    state = scope(next_check_at: ANCHOR + 1.hour, lease_token: SecureRandom.uuid, lease_expires_at: ANCHOR + 5.minutes)
    Noaa::Alerts::Fetch.expects(:call).never
    result = heartbeat
    assert_equal "leased", decision(result)[:reason]
    assert_equal state.lease_expires_at, decision(result)[:lease_expires_at]
    assert_equal 0, result.value[:invoked_count]
    assert_equal 0, result.value[:failed_count]
    refute_includes result.to_h.to_json, state.lease_token
  end

  test "ordinary acquisition retains original decision alongside completed execution" do
    state = scope
    result = heartbeat
    assert result.success?, result.value.inspect
    assert_equal "acquisition_due", decision(result)[:reason]
    assert_equal "claimed", decision(result)[:disposition]
    assert_nil decision(result)[:last_attempt_at]
    assert_nil decision(result)[:next_check_at]
    outcome = result.value[:outcomes].first[:value]
    assert_equal "successful", outcome[:disposition]
    assert_equal ANCHOR + 10.minutes, outcome[:next_check_at]
    assert_equal "noaa", outcome[:provider]
    assert_equal [ :acquisition_id, :provider, :scope_key, :decision_at, :disposition, :reason,
      :next_check_at, :lease_expires_at, :last_attempt_at, :last_success_at, :consecutive_failures,
      :last_error_code, :covered_through_at, :pending_evidence ].sort, decision(result).keys.sort
    [ :configured_count, :inspected_count, :candidate_count, :invoked_count, :successful_count ].each { |key| assert_equal 1, result.value[key] }
    assert_equal ANCHOR, state.reload.last_success_at
    refute_includes result.to_h.to_json, '"token"'
  end

  test "expired lease with durable initial window is eligible for recovery" do
    scope(lease_token: SecureRandom.uuid, lease_expires_at: ANCHOR - 1.minute, initial_window_start_at: ANCHOR - 2.days,
      last_attempt_at: ANCHOR - 1.hour, consecutive_failures: 1)
    result = heartbeat
    assert result.success?, result.value.inspect
    assert_equal "recovery_due", decision(result)[:reason]
    assert_equal 1, result.value[:invoked_count]
    assert_equal true, result.value[:outcomes].first[:value][:reclaimed_lease]
  end

  test "invalid approved geography is a configuration failure not an invocation or skip" do
    scope(query: { type: "point", latitude: 1, longitude: 2 })
    Noaa::Alerts::Fetch.expects(:call).never
    result = heartbeat
    assert result.failure?
    assert_equal "invalid", decision(result)[:disposition]
    assert_equal "unapproved_acquisition_geography", decision(result)[:reason]
    assert_equal 1, result.value[:failed_count]
    assert_equal 0, result.value[:invoked_count]
    assert_equal 0, result.value[:skipped_count]
  end

  test "outage catch up beyond ordinary lookback reports recovery using the persisted watermark" do
    scope(covered_through_at: ANCHOR - 3.days, last_success_at: ANCHOR - 3.days)
    result = heartbeat
    assert result.success?, result.value.inspect
    assert_equal "recovery_due", decision(result)[:reason]
    assert_equal ANCHOR - 3.days, decision(result)[:covered_through_at]
    assert_equal 1, result.value[:invoked_count]
  end

  test "provider failure retains eligibility and actual failure without exposing evidence" do
    scope
    Noaa::Alerts::Fetch.expects(:call).returns(ServiceResult.new(success: false, value: { code: "rate_limited" }))
    result = heartbeat
    assert result.failure?
    assert_equal "claimed", decision(result)[:disposition]
    assert_equal "acquisition_due", decision(result)[:reason]
    assert_equal "rate_limited", result.value[:outcomes].first[:value][:code]
    assert_equal 1, result.value[:invoked_count]
    assert_equal 1, result.value[:failed_count]
  end

  test "overlapping heartbeat sees existing owner without another provider request" do
    scope
    Noaa::Alerts::Fetch.expects(:call).once.with do |**_options|
      nested = heartbeat
      assert nested.success?
      assert_equal "leased", decision(nested)[:reason]
      assert_equal 1, nested.value[:skipped_count]
      assert_equal 0, nested.value[:invoked_count]
      true
    end.returns(ServiceResult.new(success: true, value: { "features" => [] }))
    assert heartbeat.success?
  end

  test "lease ownership lost during completion remains a failed claimed execution" do
    state = scope
    Noaa::Alerts::Fetch.expects(:call).with do |**_options|
      state.reload.update!(lease_token: SecureRandom.uuid)
      true
    end.returns(ServiceResult.new(success: true, value: { "features" => [] }))
    result = heartbeat
    assert result.failure?
    assert_equal "claimed", decision(result)[:disposition]
    assert_equal "alert_acquisition_superseded", result.value[:outcomes].first[:value][:code]
    assert_equal 1, result.value[:failed_count]
    assert_equal 0, result.value[:skipped_count]
  end

  test "per scope programming failure retains previous outcomes and continues" do
    first = scope
    second = scope(scope_key: "second")
    third = scope(scope_key: "third", enabled: false)
    WeatherMonitoring::AcquireAlerts.expects(:call).with(acquisition: first).returns(ServiceResult.new(success: true,
      value: { disposition: "successful", decision: { disposition: "claimed" } }))
    WeatherMonitoring::AcquireAlerts.expects(:call).with(acquisition: second).raises(ArgumentError, "PRIVATE")
    WeatherMonitoring::AcquireAlerts.expects(:call).with(acquisition: third).returns(ServiceResult.new(success: true,
      value: { disposition: "skipped", reason: "disabled" }))
    result = heartbeat
    assert result.failure?
    assert_equal 3, result.value[:inspected_count]
    assert_equal 1, result.value[:successful_count]
    assert_equal 1, result.value[:failed_count]
    assert_equal 1, result.value[:skipped_count]
    assert_equal [ first.id, second.id, third.id ], result.value[:outcomes].map { |row| row[:value][:acquisition_id] }
    assert_equal "alert_scope_execution_error", result.value[:outcomes][1][:value][:code]
    assert_equal "ArgumentError", result.value[:outcomes][1][:value][:error_class]
    refute_includes result.to_h.to_json, "PRIVATE"
  end

  test "enumeration failure is a runner error not a no op" do
    WeatherAlertAcquisition.expects(:order).raises(ActiveRecord::ConnectionNotEstablished)
    result = heartbeat
    assert result.failure?
    assert_equal "alert_scheduler_error", result.value[:code]
    assert_equal 0, result.value[:inspected_count]
    assert_empty result.value[:outcomes]
  end
end
