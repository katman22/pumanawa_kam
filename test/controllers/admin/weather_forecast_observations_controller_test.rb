require "test_helper"
require_relative "../../helpers/weather_monitoring_data"

class AdminWeatherForecastObservationsControllerTest < ActionDispatch::IntegrationTest
  include WeatherMonitoringData

  setup do
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
    admin = Admin::User.create!(username: "weather-evidence", password: "a-long-test-password", role: :canyon_admin)
    @resort = pilot_resort
    raw = fixture("brighton_grid")
    raw["properties"]["temperature"]["values"].first["value"] = nil
    data = normalized(raw)
    @observation = WeatherMonitoring::RecordObservation.call(resort: @resort, normalized: data, snapshot: snapshot(data), fetched_at: ANCHOR).value[:observation]
    post admin_login_path, params: { username: admin.username, password: "a-long-test-password" }
    HTTParty.stubs(:get).raises("Unexpected live NOAA call")
  end

  test "immutable observation is structured and has no editing controls" do
    before = @observation.attributes
    assert_no_difference [ "WeatherForecastObservation.count", "WeatherAlertObservation.count", "ResortWeatherMonitor.count" ] do
      get admin_weather_monitoring_resort_observation_path(@resort, @observation)
    end
    assert_response :success
    assert_select "body.admin-shell--canyon"
    assert_select "h1", "Forecast revision · #{@resort.resort_name}"
    assert_select "table thead th", text: "Semantic"
    assert_select "td", text: "UNKNOWN (null)"
    assert_select "th[scope='row']", text: "snowfallAmount"
    assert_select ".weather-monitoring form", count: 0
    assert_select ".weather-monitoring a[data-turbo-method]", count: 0
    assert_equal before, @observation.reload.attributes
  end

  test "nested parent swapping and missing observations return not found" do
    other = Resort.create!(resort_name: "Unrelated weather resort", slug: "unrelated-evidence", latitude: 40, longitude: -111)
    get admin_weather_monitoring_resort_observation_path(other, @observation)
    assert_response :not_found
    get admin_weather_monitoring_resort_observation_path(@resort, -1)
    assert_response :not_found
  end
end
