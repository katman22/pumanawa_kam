require "test_helper"

class ForecastControllerTest < ActionDispatch::IntegrationTest
  test "will get index and return multiple locations" do
    service_handler = OpenStruct.new(call: multi_locale_success)
    fake_service = Minitest::Mock.new
    fake_service.expect(:call, service_handler, [ "Utah" ])

    OpenCage::GeoLocation::LocationFromInput.stub :new, fake_service do
      get forecast_view_url, params: { location: "Utah" }
      assert_equal 2, assigns(:total)
      assert_equal "Utah, United States of America", assigns(:locations).first["formatted"]
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

    OpenCage::GeoLocation::LocationFromInput.stub :new, fake_service do
      Noaa::Forecast::Summary.stub :new, fake_summary_service do
        get forecast_view_url, params: { location: "Utah" }
        assert_equal 1, assigns(:total)
        assert_equal "One and Only Utah", assigns(:locations).first["formatted"]
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

    OpenCage::GeoLocation::LocationFromInput.stub :new, fake_service do
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
      get forecast_full_path, params: { lat: "39.4225192", long: "-111.714358", location_name: "One and Only Utah" }
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
      get forecast_text_only_url, params: { lat: "39.4225192", long: "-111.714358", location_name: "One and Only Utah" }
      assert_equal 58, assigns(:forecasts).first.with_indifferent_access["temperature"]
      assert_equal "Chance Showers And Thunderstorms", assigns(:forecasts).first.with_indifferent_access["shortForecast"]
      assert_response :success
    end
  end

  private

  def multi_locale_success
    OpenStruct.new(
      success?: true,
      value: { locations: [ {
                             "components" => { "postcode" => "84121" },
                             "formatted" => "Utah, United States of America",
                             "geometry" => { "lat" => 39.4225192, "lng" => -111.714358 } },
                           {
                             "components" => { "postcode" => "84121" },
                             "formatted" => "Utah County, Utah, United States of America",
                             "geometry" => { "lat" => 40.177058, "lng" => -111.6910719 } } ],
               total: 2 })
  end

  def single_locale_success
    OpenStruct.new(
      success?: true,
      value: { locations: [ {
                             "components" => { "postcode" => "84121" },
                             "formatted" => "One and Only Utah",
                             "geometry" => { "lat" => 39.4225192, "lng" => -111.714358 } }
      ],
               total: 1 })
  end

  def summary_success
    OpenStruct.new(
      success?: true,
      value: { "number" => 1,
               "name" => "Tonight",
               "isDaytime" => false,
               "temperature" => 36,
               "temperatureUnit" => "F",
               "probabilityOfPrecipitation" => { "unitCode" => "wmoUnit:percent", "value" => nil },
               "windSpeed" => "7 mph",
               "windDirection" => "W",
               "icon" => nil,
               "shortForecast" => "Mostly Clear",
               "detailedForecast" => "Mostly clear. Low around 36, with temperatures rising to around 38 overnight. West wind around 7 mph.",
               "high" => 56,
               "low" => 36,
               "latitude" => 40.6018223,
               "longitude" => -111.583314,
               "from_cache" => true })
  end

  def forecast_success
    OpenStruct.new(
      success?: true,
      value: {
        "forecasts" => [
          {
            "number": 1,
            "name": "This Afternoon",
            "startTime": "2025-05-07T12:00:00-06:00",
            "endTime": "2025-05-07T18:00:00-06:00",
            "isDaytime": true,
            "temperature": 58,
            "temperatureUnit": "F",
            "temperatureTrend": "",
            "probabilityOfPrecipitation": {
              "unitCode": "wmoUnit:percent",
              "value": 50
            },
            "windSpeed": "7 mph",
            "windDirection": "NW",
            "icon": "https://api.weather.gov/icons/land/day/tsra_sct,50?size=medium",
            "shortForecast": "Chance Showers And Thunderstorms",
            "detailedForecast": "A chance of showers and thunderstorms. Partly sunny, with a high near 58. Northwest wind around 7 mph. Chance of precipitation is 50%."
          }
        ]
      })
  end
end
