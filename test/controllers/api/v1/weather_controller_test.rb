require "test_helper"
require_relative "../../../helpers/forecast_test_helper"

class Api::V1::WeatherControllerTest < ActionDispatch::IntegrationTest
  include ForecastTestHelper
  test "bad token receive error" do
    get api_v1_weather_index_url(location: "Utah"), headers: erred_auth_headers

    assert_response :unauthorized
  end

  test "will get index and a location" do
    service_handler = OpenStruct.new(call: multi_locale_success)
    fake_service = Minitest::Mock.new
    fake_service.expect(:call, service_handler, [ "Utah" ])
    Google::GeoLocate.stub :new, fake_service do
      get api_v1_weather_index_url(location: "Utah"), headers: auth_headers
      locations = JSON.parse(response.body)
      puts locations
      first_location = locations.first
      assert_equal "Utah, United States of America", first_location["name"]
      assert_response :success
    end
  end

  test "will get forecasts for a location" do
    forecast_service_handler = OpenStruct.new(call: forecast_success)
    fake_forecast_service = Minitest::Mock.new
    fake_forecast_service.expect(:call, forecast_service_handler, %w[39.4225192 -111.714358])
    host! "www.auraweatherforecasts.com"
    Noaa::Forecast::TextOnly.stub :new, fake_forecast_service do
      get mobile_forecast_full_path, params: { lat: "39.4225192", long: "-111.714358", location_name: "One and Only Utah", country_code: "us" }
      assert_match "Chance Showers And Thunderstorms", response.body
      assert_response :success
    end
  end
end
