require "test_helper"
require_relative "../../helpers/weather_monitoring_data"

class AdminWeatherMonitoringTabsTest < ActionDispatch::IntegrationTest
  include WeatherMonitoringData

  setup do
    travel_to ANCHOR
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
    @admin = Admin::User.create!(username: "tabs-operator", password: "a-long-test-password", role: :canyon_admin)
    @resort = pilot_resort
    @monitor = ResortWeatherMonitor.create!(resort: @resort, enabled: true)
    HTTParty.stubs(:get).raises("Unexpected live NOAA call")
    sign_in(@admin)
  end

  teardown { travel_back }

  def sign_in(user)
    post admin_login_path, params: { username: user.username, password: "a-long-test-password" }
  end

  def acquisition(**attributes)
    WeatherAlertAcquisition.create!({ scope_key: WeatherAlertAcquisition::PILOT_SCOPE,
      query: { type: "point", latitude: 40.5986, longitude: -111.5845 } }.merge(attributes))
  end

  def signal(index, resorts: [ @resort ])
    source = WeatherAlertObservation.create!(provider: "noaa", source_identifier: "urn:tabs-#{index}",
      content_sha256: Digest::SHA256.hexdigest(index.to_s), first_seen_at: ANCHOR, source_sent_at: ANCHOR,
      event: "High Wind Warning", status: "Actual", message_type: "Update", evidence: { description: "PRIVATE NOAA BODY" })
    signal = WeatherAlertSignal.create!(weather_alert_observation: source, signal_type: "updated",
      detected_at: ANCHOR + index.minutes, change_details: { fields: [ "severity", "instruction" ] })
    resorts.each { |resort| WeatherAlertSignalResort.create!(weather_alert_signal: signal, resort: resort, associated_at: ANCHOR, evidence: { method: "test" }) }
    signal
  end

  def queries_for(path)
    queries = []
    listener = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] if payload[:sql].start_with?("SELECT") && payload[:name] != "SCHEMA" }
    ActiveSupport::Notifications.subscribed(listener, "sql.active_record") { get path }
    assert_response :success
    queries
  end

  test "tabs have stable routes one active link and meaningful empty states" do
    assert_routing "/admin/weather_monitoring/alerts", controller: "admin/weather_monitoring", action: "alerts"
    assert_routing "/admin/weather_monitoring/history", controller: "admin/weather_monitoring", action: "history"
    [ [ admin_weather_monitoring_path, "Forecasts" ], [ admin_weather_monitoring_alerts_path, "Alerts" ],
      [ admin_weather_monitoring_history_path, "History" ] ].each do |path, label|
      2.times do
        get path
        assert_response :success
        assert_select "nav.weather-tabs a[aria-current='page']", text: label, count: 1
        assert_select "nav.weather-tabs a", count: 3
        assert_select "body.admin-shell--canyon"
      end
    end
    get admin_weather_monitoring_alerts_path
    assert_select ".weather-tab-content", text: /No geographic alert acquisition scopes/
    assert_select ".weather-tab-content", text: /No alert signals have been recorded/
    assert_select ".weather-tab-content form", count: 0
    get admin_weather_monitoring_history_path
    assert_select "a[href=?]", admin_weather_monitoring_resort_path(@resort, locale: :en, tab: "evidence", anchor: "forecast-history")
    @monitor.destroy!
    get admin_weather_monitoring_history_path
    assert_select ".weather-tab-content", text: /No forecast monitors are configured/
  end

  test "scopes show completion backoff leases and recovery without exposing private evidence" do
    scope = acquisition(enabled: true, last_attempt_at: ANCHOR, last_success_at: ANCHOR - 1.hour,
      next_check_at: ANCHOR + 1.hour, consecutive_failures: 2, last_error_code: "rate_limited",
      last_result: { success: false, code: "rate_limited", private: "PRIVATE RESULT" },
      lease_token: SecureRandom.uuid, lease_expires_at: ANCHOR + 2.minutes,
      initial_window_start_at: ANCHOR - 8.days, pending_evidence: { private: "PRIVATE RECEIPT" },
      covered_from_at: ANCHOR - 1.day, covered_through_at: ANCHOR - 1.hour,
      coverage_gaps: [ { from: (ANCHOR - 8.days).iso8601, through: (ANCHOR - 6.days).iso8601 } ])
    acquisition(scope_key: "future-disabled", last_result: { success: true })
    before = scope.attributes
    get admin_weather_monitoring_alerts_path
    assert_response :success
    assert_select "[data-state='enabled']"
    assert_select "[data-state='disabled']"
    assert_select ".weather-tab-content", text: /40.5986, -111.5845/
    assert_select ".weather-tab-content", text: /Failed/
    assert_select ".weather-tab-content", text: /Successful/
    assert_select ".weather-tab-content", text: /Retry\/backoff/
    assert_select ".weather-tab-content", text: /Pending evidence retained/
    assert_select ".weather-tab-content", text: /Active/
    assert_select "details summary", text: /1 permanent gaps/
    assert_select "time[datetime=?]", (ANCHOR - 8.days).iso8601
    assert_select "time[datetime=?]", (ANCHOR + 1.hour).iso8601
    [ scope.lease_token, "PRIVATE RESULT", "PRIVATE RECEIPT" ].each { |private_value| refute_includes response.body, private_value }
    assert_equal before, scope.reload.attributes
    assert_select ".weather-tab-content form", count: 0
  end

  test "signals preserve shared source identity multiple resort associations and bounded ordering" do
    other = Resort.create!(slug: "association-fixture", resort_name: "Shared resort", latitude: 40, longitude: -111)
    records = 27.times.map { |index| signal(index, resorts: [ @resort, other ]) }
    get admin_weather_monitoring_alerts_path
    assert_response :success
    assert_equal records.reverse.first(25).map { |row| row.id.to_s }, css_select("tr[data-signal-id]").map { |row| row["data-signal-id"] }
    assert_select "tbody tr", count: 25
    assert_select "tbody", text: /Shared resort/
    assert_select "tbody", text: /#{@resort.resort_name}/
    assert_select "tbody", text: /High Wind Warning/
    assert_select "tbody", text: /urn:tabs-26/
    assert_select "tbody", text: /severity, instruction/
    refute_includes response.body, "PRIVATE NOAA BODY"
  end

  test "tabs avoid hidden history queries eager load signals and never invoke monitoring" do
    WeatherMonitoring::ScheduledRun.expects(:call).never
    WeatherMonitoring::AcquireAlerts.expects(:call).never
    WeatherMonitoring::RunEvaluation.expects(:call).never
    scope = acquisition
    before = [ scope.attributes, @monitor.attributes ]
    signal(1)
    first = queries_for(admin_weather_monitoring_alerts_path)
    assert_no_match /weather_forecast_observations|resort_weather_monitors/, first.join
    3.times { |index| signal(index + 2) }
    assert_equal first.size, queries_for(admin_weather_monitoring_alerts_path).size
    assert_no_difference [ "WeatherAlertAcquisition.count", "ResortWeatherMonitor.count", "WeatherAlertObservation.count", "WeatherAlertSignal.count" ] do
      history = queries_for(admin_weather_monitoring_history_path)
      assert_no_match /weather_forecast_observations|weather_alert_signals|weather_alert_acquisitions/, history.join
      forecasts = queries_for(admin_weather_monitoring_path)
      assert_no_match /weather_alert_signals|weather_alert_acquisitions/, forecasts.join
    end
    assert_equal before, [ scope.reload.attributes, @monitor.reload.attributes ]
  end

  test "Canyon authorization protects both tabs including inactive and logged out users" do
    %w[super_admin mural_admin mahi_tahi_admin organization_admin].each do |role|
      user = Admin::User.create!(username: "tabs-#{role}", role: role, password: "a-long-test-password")
      sign_in(user)
      [ admin_weather_monitoring_alerts_path, admin_weather_monitoring_history_path ].each do |path|
        get path
        assert_response role == "super_admin" ? :success : :forbidden
      end
    end
    sign_in(@admin)
    @admin.update!(active: false)
    get admin_weather_monitoring_alerts_path
    assert_redirected_to admin_login_path(locale: :en)
    get admin_weather_monitoring_history_path
    assert_redirected_to admin_login_path(locale: :en)
  end
end
