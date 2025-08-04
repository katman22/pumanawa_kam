require "test_helper"
require_relative "../helpers/forecast_test_helper"

class ForecastControllerTest < ActionDispatch::IntegrationTest
  include ForecastTestHelper

  test "will get index and return multiple locations" do
    service_handler = OpenStruct.new(call: multi_locale_success)
    fake_service = Minitest::Mock.new
    fake_service.expect(:call, service_handler, [ "Utah" ])

    Google::GeoLocate.stub :new, fake_service do
      get forecast_view_url, params: { location: "Utah" }
      assert_equal 2, assigns(:total)
      assert_equal "Utah, United States of America", assigns(:locations).first[:name]
      assert_response :success
    end
  end

  test "will get index and return one location with a summary" do
    locale_service_handler = OpenStruct.new(call: single_locale_success)
    fake_service = Minitest::Mock.new
    fake_service.expect(:call, locale_service_handler, [ "Utah" ])

    summary_service_handler = OpenStruct.new(call: summary_success)
    fake_summary_service = Minitest::Mock.new
    fake_summary_service.expect(:call, summary_service_handler, [ 39.4225192, -111.714358 ])

    Google::GeoLocate.stub :new, fake_service do
      Noaa::Forecast::Summary.stub :new, fake_summary_service do
        get forecast_view_url, params: { location: "Utah" }
        assert_equal 1, assigns(:total)
        assert_equal "One and Only Utah", assigns(:locations).first[:name]
        assert_response :success
      end
    end
  end

  test "will get a summary for locale" do
    summary_service_handler = OpenStruct.new(call: summary_success)
    fake_summary_service = Minitest::Mock.new
    fake_summary_service.expect(:call, summary_service_handler, %w[39.4225192 -111.714358])

    Noaa::Forecast::Summary.stub :new, fake_summary_service do
      post forecast_summary_path, params: { lat: "39.4225192", long: "-111.714358", location_name: "One and Only Utah" }
      assert_match "One and Only Utah", response.body
      assert_match "Mostly Clear", response.body
      assert_response :success
    end

  end

  test "will get multiple locations from geo location input" do
    service_handler = OpenStruct.new(call: multi_locale_success)
    fake_service = Minitest::Mock.new
    fake_service.expect(:call, service_handler, [ "Utah" ])

    Google::GeoLocate.stub :new, fake_service do
      post forecast_geo_location_url, params: { location: "Utah" }
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
      get forecast_full_path, params: { lat: "39.4225192", long: "-111.714358", location_name: "One and Only Utah", country_code: "us" }
      assert_equal 58, assigns(:forecasts).first.with_indifferent_access["temperature"]
      # assert_equal "Mostly Clear", assigns(:summary)["shortForecast"]
      assert_response :success
    end
  end

  test "will get a text only forecast for locale" do
    forecast_service_handler = OpenStruct.new(call: forecast_success)
    fake_forecast_service = Minitest::Mock.new
    fake_forecast_service.expect(:call, forecast_service_handler, %w[39.4225192 -111.714358])

    Noaa::Forecast::TextOnly.stub :new, fake_forecast_service do
      get forecast_text_only_url, params: { lat: "39.4225192", long: "-111.714358", location_name: "One and Only Utah", country_code: "us" }
      assert_equal 58, assigns(:forecasts).first.with_indifferent_access["temperature"]
      assert_equal "Chance Showers And Thunderstorms", assigns(:forecasts).first.with_indifferent_access["shortForecast"]
      assert_response :success
    end
  end
end
