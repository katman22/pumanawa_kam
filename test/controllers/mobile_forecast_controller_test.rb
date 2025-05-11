require "test_helper"

class MobileForecastControllerTest < ActionDispatch::IntegrationTest
  test "will get index" do
    service_handler = OpenStruct.new(call: multi_locale_success)
    fake_service = Minitest::Mock.new
    fake_service.expect(:call, service_handler, [ "Utah" ])

    OpenCage::GeoLocation::LocationFromInput.stub :new, fake_service do
      get mobile_forecast_index_url, params: { location: "Utah" }
      assert_match "Utah County, Utah, United States of America", response.body
      assert_response :success
    end
  end

  test "will get multi locations" do
    service_handler = OpenStruct.new(call: multi_locale_success)
    fake_service = Minitest::Mock.new
    fake_service.expect(:call, service_handler, [ "Utah" ])

    OpenCage::GeoLocation::LocationFromInput.stub :new, fake_service do
      post mobile_forecast_geo_location_path, params: { location: "Utah" }
      assert_match "Total Locations: 2", response.body
      assert_match "Utah, United States of America", response.body
      assert_response :success
    end
  end

  test "will get a full forecast for locale" do
    forecast_service_handler = OpenStruct.new(call: forecast_success)
    fake_forecast_service = Minitest::Mock.new
    fake_forecast_service.expect(:call, forecast_service_handler, %w[39.4225192 -111.714358])

    Noaa::Forecast::TextOnly.stub :new, fake_forecast_service do
      get mobile_forecast_full_path, params: { lat: "39.4225192", long: "-111.714358", location_name: "One and Only Utah" }
      assert_match "Chance Showers And Thunderstorms", response.body
      assert_response :success
    end
  end
end
