require "test_helper"
require_relative "../../helpers/weather_monitoring_data"

class AdminWeatherMonitoringControllerTest < ActionDispatch::IntegrationTest
  include WeatherMonitoringData

  setup do
    travel_to ANCHOR
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
    @admin = Admin::User.create!(username: "weather-operator", password: "a-long-test-password", role: :canyon_admin)
    @resort = pilot_resort
    data = normalized
    @observation = WeatherMonitoring::RecordObservation.call(resort: @resort, normalized: data, snapshot: snapshot(data), fetched_at: ANCHOR).value[:observation]
    @mapping = fixture("brighton_points")["properties"].merge("latitude" => @resort.latitude, "longitude" => @resort.longitude)
    @monitor = ResortWeatherMonitor.create!(resort: @resort, enabled: true, current_forecast_observation: @observation,
      mapping: @mapping, mapping_checked_at: ANCHOR, monitoring_level: "approaching", last_checked_at: ANCHOR, last_success_at: ANCHOR,
      next_check_at: ANCHOR + 6.hours, next_probe_at: ANCHOR + 12.hours, last_alert_checked_at: ANCHOR,
      last_decision: { quality: "complete", evaluation_at: ANCHOR.iso8601, reasons: [], change: { disposition: "no_baseline" }, alerts: { state: "available" } })
    HTTParty.stubs(:get).raises("Unexpected live NOAA call")
    sign_in(@admin)
  end

  teardown { travel_back }

  def sign_in(admin)
    post admin_login_path, params: { username: admin.username, password: "a-long-test-password" }
    assert_redirected_to admin_root_path(locale: :en)
  end

  def monitor_path(resort = @resort)
    admin_weather_monitoring_resort_path(resort)
  end

  test "index is Canyon themed and displays distinct check and probe state without writes" do
    @monitor.update!(failure_count: 2, last_error_code: "transport_error", last_error_at: ANCHOR)
    WeatherMonitoring::EvaluateResort.expects(:call).never
    before = @resort.attributes
    assert_no_difference [ "ResortWeatherMonitor.count", "WeatherForecastObservation.count", "WeatherAlertObservation.count" ] do
      get admin_weather_monitoring_path
    end
    assert_response :success
    assert_select "body.admin-shell--canyon"
    assert_select "h1", "Weather Monitoring"
    assert_select "article#resort_weather_monitor_#{@monitor.id}" do
      assert_select "a[href=?]", admin_weather_monitoring_resort_path(@resort, locale: :en), text: @resort.resort_name
      assert_select "[data-snowfall='current']", "4.2″"
      assert_select "[data-due='check'] time[datetime=?]", (ANCHOR + 6.hours).iso8601
      assert_select "[data-due='probe'] time[datetime=?]", (ANCHOR + 12.hours).iso8601
      assert_select ".weather-error", "transport_error"
      assert_select "[data-state='complete']"
    end
    assert_equal before, @resort.reload.attributes
  end

  test "missing evidence and unknown latest decision never render zero snowfall" do
    @monitor.update!(current_forecast_observation: nil, last_decision: {})
    get admin_weather_monitoring_path
    assert_response :success
    assert_select "[data-snowfall='current']", "UNKNOWN"
    @monitor.update!(current_forecast_observation: @observation, last_decision: { quality: "unknown" })
    get admin_weather_monitoring_path
    assert_select "[data-snowfall='current']", "UNKNOWN · inspect recorded evidence"
  end

  test "detail renders bounded snowfall decisions quality and immutable snapshot window" do
    get monitor_path
    assert_response :success
    assert_select "#current-forecast .weather-snow-total", "4.2″"
    assert_select "tr[data-bucket='48-72'] td", text: "0–2.1″ (bounded)"
    assert_select "tr[data-bucket='72-120'] td", text: "2.1–4.2″ (bounded)"
    assert_select "#monitor-decision li", "Snow candidate 48–72 hours away"
    assert_select "#monitor-decision li", "No previous forecast baseline"
    assert_select "#source-quality", text: /2669 m \(NOAA grid\)/
    assert_select "#current-forecast", text: /immutable snapshot/
    assert_select "details summary", text: "Raw persisted decision"
    assert_select "#source-quality table", text: /120 h known/
    assert_select "#current-forecast", text: /Maximum precipitation probability · recorded window/
  end

  test "partial and unsupported snow evidence remain diagnosable on detail" do
    raw = fixture("brighton_grid")
    raw["properties"]["snowfallAmount"]["values"].select! { |row| Time.iso8601(row["validTime"].split("/").first) < ANCHOR + 4.days }
    data = normalized(raw)
    observation = WeatherMonitoring::RecordObservation.call(resort: @resort, normalized: data, snapshot: snapshot(data), fetched_at: ANCHOR).value[:observation]
    @monitor.update!(current_forecast_observation: observation, last_decision: { quality: "partial" })
    get monitor_path
    assert_response :success
    assert_select "#current-forecast .weather-snow-total", text: /PARTIAL/
    assert_select "#source-quality", text: /Gap:/
    raw["properties"]["snowfallAmount"]["uom"] = "unknown_unit"
    data = normalized(raw)
    observation = WeatherMonitoring::RecordObservation.call(resort: @resort, normalized: data, snapshot: snapshot(data), fetched_at: ANCHOR).value[:observation]
    @monitor.update!(current_forecast_observation: observation, last_decision: { quality: "unknown" })
    get monitor_path
    assert_select "#current-forecast .weather-snow-total", "UNKNOWN"
    assert_select "#source-quality", text: /Unsupported unit or value/
  end

  test "forecast history is sorted and bounded without changing evidence" do
    records = 27.times.map do |index|
      WeatherForecastObservation.create!(@observation.attributes.except("id").merge("first_fetched_at" => ANCHOR + index.minutes,
        "content_sha256" => Digest::SHA256.hexdigest("weather-history-#{index}")))
    end
    get monitor_path
    assert_response :success
    assert_select "#forecast-history tbody tr", count: 25
    assert_equal records.reverse.first(25).map(&:id).map(&:to_s), css_select("#forecast-history tr[data-observation-id]").map { |row| row["data-observation-id"] }
    assert_select "#forecast-history a[href=?]", admin_weather_monitoring_resort_observation_path(@resort, records.last, locale: :en)
    assert_equal 28, WeatherForecastObservation.count
  end

  test "alerts match exact forecast zone and show persisted probe context and references" do
    WeatherMonitoring::RecordAlertObservations.call(collection: fixture("ut_winter_alert_updates"), zone_ids: [ "UTZ111" ], seen_at: ANCHOR)
    related = WeatherAlertObservation.first
    WeatherAlertObservation.create!(related.attributes.except("id").merge("source_identifier" => "unrelated-alert",
      "affected_zone_ids" => [ "UTZ1110" ], "evidence" => { "headline" => "Unrelated mountain message" }))
    @monitor.update!(active_alert_identifiers: [ related.source_identifier ])
    get monitor_path
    assert_response :success
    assert_select "#alert-history .weather-alert", count: 2
    assert_select "#alert-history", text: /Identifier listed active at last successful probe/
    assert_select "#alert-history", text: /Update references and source evidence/
    assert_select "#alert-history", text: /Unrelated mountain message/, count: 0
    assert_select "#alert-history pre", text: /references/
  end

  test "empty monitoring overview provides safe Brighton entry and GET creates nothing" do
    @monitor.destroy!
    get admin_weather_monitoring_path
    assert_response :success
    assert_select "a[href=?]", admin_weather_monitoring_resort_path(@resort, locale: :en), text: "Open Brighton pilot"
    assert_no_difference "ResortWeatherMonitor.count" do
      get monitor_path
    end
    assert_select "form[action=?]", enable_admin_weather_monitoring_resort_path(@resort, locale: :en)
  end

  test "roles enforce reads and controls server side and navigation follows capability" do
    %w[mural_admin mahi_tahi_admin organization_admin super_admin].each do |role|
      user = Admin::User.create!(username: "weather-#{role}", password: "a-long-test-password", role: role)
      sign_in(user)
      allowed = role == "super_admin"
      get admin_root_path
      assert_select "nav a[href=?]", admin_weather_monitoring_path(locale: :en), count: allowed ? 1 : 0
      get admin_weather_monitoring_path
      assert_response allowed ? :success : :forbidden
      get monitor_path
      assert_response allowed ? :success : :forbidden
      get admin_weather_monitoring_resort_observation_path(@resort, @observation)
      assert_response allowed ? :success : :forbidden
      next if allowed

      assert_no_difference [ "ResortWeatherMonitor.count", "WeatherForecastObservation.count" ] do
        patch disable_admin_weather_monitoring_resort_path(@resort)
        assert_response :forbidden
        post evaluate_admin_weather_monitoring_resort_path(@resort)
        assert_response :forbidden
        post probe_admin_weather_monitoring_resort_path(@resort)
        assert_response :forbidden
      end
      assert @monitor.reload.enabled?
    end
  end

  test "unauthenticated and inactive sessions cannot access monitoring" do
    @admin.update!(active: false)
    get monitor_path
    assert_redirected_to admin_login_path(locale: :en)
    post evaluate_admin_weather_monitoring_resort_path(@resort)
    assert_redirected_to admin_login_path(locale: :en)
  end

  test "authorized controls enable and disable only monitoring without changing Resort or evidence" do
    @monitor.update!(enabled: false)
    before = @resort.attributes
    assert_no_difference [ "WeatherForecastObservation.count", "WeatherAlertObservation.count" ] do
      patch enable_admin_weather_monitoring_resort_path(@resort), params: { resort_weather_monitor: { mapping: { gridId: "forged" } } }
      assert_response :see_other
      assert @monitor.reload.enabled?
      assert_equal "SLC", @monitor.mapping["gridId"]
      patch disable_admin_weather_monitoring_resort_path(@resort)
      assert_response :see_other
      refute @monitor.reload.enabled?
    end
    assert_equal before, @resort.reload.attributes
  end

  test "manual evaluation and probe call existing service synchronously" do
    [ [ false, evaluate_admin_weather_monitoring_resort_path(@resort) ], [ true, probe_admin_weather_monitoring_resort_path(@resort) ] ].each do |probe, path|
      WeatherMonitoring::EvaluateResort.expects(:call).with(resort: @resort, persist: true, probe: probe).returns(ServiceResult.new(success: true, value: {}))
      post path
      assert_redirected_to admin_weather_monitoring_resort_path(@resort, locale: :en)
      assert_response :see_other
    end
  end

  test "service failure is displayed with a safe code and no provider body" do
    WeatherMonitoring::EvaluateResort.expects(:call).returns(ServiceResult.new(success: false, value: { code: "transport_error", details: "PRIVATE PROVIDER BODY" }))
    post evaluate_admin_weather_monitoring_resort_path(@resort)
    follow_redirect!
    assert_select "[role='status']", text: /transport_error/
    assert_no_match /PRIVATE PROVIDER BODY/, response.body
  end

  test "GET cannot mutate controls and non Brighton pilot actions are forbidden" do
    WeatherMonitoring::EvaluateResort.expects(:call).never
    paths = [ enable_admin_weather_monitoring_resort_path(@resort), disable_admin_weather_monitoring_resort_path(@resort),
      evaluate_admin_weather_monitoring_resort_path(@resort), probe_admin_weather_monitoring_resort_path(@resort) ]
    paths.each do |path|
      get path
      assert_response :not_found
    end
    other = Resort.create!(resort_name: "Future monitored resort", slug: "future-monitor", latitude: 40, longitude: -111)
    get monitor_path(other)
    assert_response :success
    assert_select ".weather-controls", count: 0
    patch enable_admin_weather_monitoring_resort_path(other)
    assert_response :forbidden
    post evaluate_admin_weather_monitoring_resort_path(other)
    assert_response :forbidden
    post probe_admin_weather_monitoring_resort_path(other)
    assert_response :forbidden
    refute ResortWeatherMonitor.exists?(resort: other)
  end

  test "pilot mutation requires CSRF token" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    @monitor.update!(enabled: false)
    patch enable_admin_weather_monitoring_resort_path(@resort)
    assert_response :unprocessable_entity
    refute @monitor.reload.enabled?
    get monitor_path
    token = css_select("meta[name='csrf-token']").first["content"]
    patch enable_admin_weather_monitoring_resort_path(@resort), params: { authenticity_token: token }
    assert_response :see_other
    assert @monitor.reload.enabled?
    WeatherMonitoring::EvaluateResort.expects(:call).never
    post evaluate_admin_weather_monitoring_resort_path(@resort)
    assert_response :unprocessable_entity
    post probe_admin_weather_monitoring_resort_path(@resort)
    assert_response :unprocessable_entity
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "index projections avoid large interval columns and N plus one reads" do
    queries = monitoring_queries
    forecast_sql = queries.select { |sql| sql.include?('FROM "weather_forecast_observations"') }
    assert_equal 1, forecast_sql.size
    assert_no_match /selected_intervals|source_metadata/, forecast_sql.first
    other = Resort.create!(resort_name: "Other monitored resort", slug: "weather-extra", latitude: 40, longitude: -111)
    ResortWeatherMonitor.create!(resort: other)
    assert_equal queries.size, monitoring_queries.size
  end

  test "missing resort returns not found" do
    get admin_weather_monitoring_resort_path(-1)
    assert_response :not_found
  end

  def monitoring_queries
    queries = []
    listener = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] if payload[:sql].start_with?("SELECT") && payload[:name] != "SCHEMA" }
    ActiveSupport::Notifications.subscribed(listener, "sql.active_record") { get admin_weather_monitoring_path }
    assert_response :success
    queries
  end
end
