require "test_helper"
require_relative "../../../helpers/weather_monitoring_data"

class Api::V1::WeatherMonitorsControllerTest < ActionDispatch::IntegrationTest
  include WeatherMonitoringData

  setup do
    travel_to ANCHOR
    @user = User.create!(role: "user", status: "active")
    @resort = pilot_resort
    HomeResort.create!(user: @user, resort: @resort, kind: :subscribed)
    @data = normalized
    @observation = WeatherMonitoring::RecordObservation.call(resort: @resort, normalized: @data, snapshot: snapshot(@data), fetched_at: ANCHOR).value[:observation]
    @monitor = ResortWeatherMonitor.create!(resort: @resort, enabled: true, current_forecast_observation: @observation,
      last_success_at: ANCHOR, next_check_at: ANCHOR + 6.hours, last_decision: { quality: "complete" })
    HTTParty.stubs(:get).raises("Unexpected live NOAA request")
    WeatherMonitoring::RunEvaluation.expects(:call).never
    WeatherMonitoring::AcquireAlerts.expects(:call).never
  end

  teardown { travel_back }

  def headers_for(user = @user)
    { "Authorization" => "Bearer #{JwtToken.issue({ user_id: user.id })}" }
  end

  def summary(resort = @resort, headers: headers_for)
    get "/api/v1/weather/monitor", params: { resort_id: resort.slug }, headers: headers
    response.parsed_body
  end

  test "authenticated summary preserves immutable buckets bounds and excludes operational details" do
    before = [ @monitor.attributes, @observation.attributes ]
    assert_no_difference [ "WeatherForecastObservation.count", "ResortWeatherMonitor.count", "WeatherAlertSignal.count" ] do
      body = summary
      assert_response :success
      assert_equal 1, body["schema_version"]
      assert_equal "brighton", body.dig("resort", "slug")
      assert_equal "available", body.dig("availability", "state")
      assert_equal 106.68, body.dig("forecast", "snowfall", "total", "amount_mm")
      assert_equal [ [ 0, 24 ], [ 24, 48 ], [ 48, 72 ], [ 72, 120 ] ], body.dig("forecast", "snowfall", "buckets").map { |row| row["hours"] }
      bucket = body.dig("forecast", "snowfall", "buckets")[2]
      assert_nil bucket["amount_mm"]
      assert_equal 0, bucket["lower_mm"]
      assert_equal 53.34, bucket["upper_mm"]
      assert_equal ANCHOR.iso8601, body.dig("forecast", "window", "start_at")
      assert_equal "complete", body.dig("forecast", "quality", "state")
      assert_equal "private, no-store", response.headers["Cache-Control"]
      %w[next_check_at next_probe_at lease pending_evidence content_sha256 source_metadata selected_intervals mapping last_error_code].each do |internal|
        refute_includes response.body, internal
      end
    end
    assert_equal before, [ @monitor.reload.attributes, @observation.reload.attributes ]
  end

  test "read time freshness never recalculates or moves the saved forecast window" do
    original = summary.fetch("forecast")
    travel_to ANCHOR + 6.days
    current = summary.fetch("forecast")
    assert_equal "stale", current.dig("freshness", "state")
    assert_equal true, current.dig("freshness", "window_expired")
    assert_equal original["snowfall"], current["snowfall"]
    assert_equal original["window"], current["window"]
    assert_equal original["recorded_at"], current["recorded_at"]
    assert_equal "fresh", current.dig("quality", "freshness_at_recording")
  end

  test "partial and unknown evidence do not turn into zero or clear" do
    raw = fixture("brighton_grid")
    raw["properties"]["snowfallAmount"]["values"] = []
    data = normalized(raw)
    record = WeatherMonitoring::RecordObservation.call(resort: @resort, normalized: data, snapshot: snapshot(data), fetched_at: ANCHOR).value[:observation]
    @monitor.update!(current_forecast_observation: record, last_decision: { quality: "unknown" })
    body = summary
    assert_equal "unknown", body.dig("forecast", "quality", "state")
    assert_nil body.dig("forecast", "snowfall", "total", "amount_mm")
    assert_nil body.dig("forecast", "snowfall", "total", "upper_mm")
    assert_equal "unknown", body.dig("monitoring", "last_evaluation_quality")
  end

  test "disabled missing snapshot and other resort monitoring degrade without writes" do
    @monitor.update!(enabled: false)
    assert_equal "monitor_disabled", summary.dig("availability", "reason")
    assert_nil response.parsed_body["forecast"]
    @monitor.update!(enabled: true, current_forecast_observation: nil)
    assert_equal "no_snapshot", summary.dig("availability", "reason")
    @monitor.destroy!
    assert_no_difference "ResortWeatherMonitor.count" do
      assert_equal "monitor_missing", summary.dig("availability", "reason")
    end
    other = Resort.create!(resort_name: "Another resort", slug: "other-pilot", latitude: 40, longitude: -111)
    HomeResort.create!(user: @user, resort: other, kind: :subscribed)
    assert_equal "pilot_only", summary(other).dig("availability", "reason")
    assert_nil response.parsed_body["forecast"]
  end

  test "auth entitlement and account boundaries remain server authoritative" do
    summary(headers: {})
    assert_response :unauthorized
    summary(headers: { "Authorization" => "Bearer invalid" })
    assert_response :unauthorized
    outsider = User.create!(role: "user", status: "active")
    summary(headers: headers_for(outsider))
    assert_response :forbidden
    HomeResort.create!(user: outsider, resort: @resort, kind: :free)
    summary(headers: headers_for(outsider))
    assert_response :forbidden
    Entitlements::Resolver.stubs(:call).returns(ServiceResult.new(success: true, value: { tier: "premium" }))
    summary(headers: headers_for(outsider))
    assert_response :success
    @user.update!(status: "disabled")
    summary
    assert_response :unauthorized
  end

  test "missing resort is 404 and entitlement failure is not disguised as success" do
    get "/api/v1/weather/monitor", params: { resort_id: "missing" }, headers: headers_for
    assert_response :not_found
    Entitlements::Resolver.stubs(:call).returns(ServiceResult.new(success: false, value: { private: "NOT PUBLIC" }))
    summary
    assert_response :service_unavailable
    refute_includes response.body, "NOT PUBLIC"
  end
end
