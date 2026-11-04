require "test_helper"

class WeatherAlertAcquisitionTest < ActiveSupport::TestCase
  test "scope state is disabled by default unique and not a resort relationship" do
    state = WeatherAlertAcquisition.create!(scope_key: "test-geographic-scope", query: { type: "point", latitude: 40, longitude: -111 })
    refute state.enabled?
    assert_equal 0, state.consecutive_failures
    assert_nil state.covered_through_at
    assert_nil state.initial_window_start_at
    assert_nil state.pending_evidence
    refute state.has_attribute?(:resort_id)
    refute WeatherAlertAcquisition.new(scope_key: state.scope_key).valid?
    assert_raises(ActiveRecord::RecordNotUnique) do
      WeatherAlertAcquisition.transaction(requires_new: true) do
        WeatherAlertAcquisition.insert_all!([ { provider: "noaa", scope_key: state.scope_key, created_at: Time.current, updated_at: Time.current } ])
      end
    end
  end

  test "persisted geographic identity cannot silently change under existing coverage" do
    state = WeatherAlertAcquisition.create!(scope_key: "immutable-query", query: { type: "point", latitude: 40, longitude: -111 })
    refute state.update(query: { type: "area", area: "UT" })
    assert_includes state.errors[:query].first, "cannot change"
    assert_equal "point", state.reload.query["type"]
    assert state.update(enabled: true)
  end

  test "database rejects negative counters and incomplete leases" do
    state = WeatherAlertAcquisition.create!(scope_key: "constraints")
    assert_raises(ActiveRecord::StatementInvalid) do
      WeatherAlertAcquisition.transaction(requires_new: true) { state.update_columns(consecutive_failures: -1) }
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      WeatherAlertAcquisition.transaction(requires_new: true) { state.update_columns(lease_token: SecureRandom.uuid) }
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      WeatherAlertAcquisition.transaction(requires_new: true) { state.update_columns(pending_evidence: []) }
    end
  end
end
