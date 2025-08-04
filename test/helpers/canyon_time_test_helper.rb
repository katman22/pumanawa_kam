# frozen_string_literal: true

module ForecastTestHelper
  def multi_locale_success
    OpenStruct.new(
      success?: true,
      value: [
          {
            "lat": 39.4225192,
            "lng": -111.714358,
            "country": "United States of America",
            "country_code": "us",
            "name": "Utah, United States of America"
          },
          {
            "lat": 40.177058,
            "lng": -111.6910719,
            "country": "United States of America",
            "country_code": "us",
            "name": "Utah County, Utah, United States of America"
          }
        ])
  end

  def single_locale_success
    OpenStruct.new(
      success?: true,
      value: [
        {
          "lat": 39.4225192,
          "lng": -111.714358,
          "country": "United States of America",
          "country_code": "us",
          "name": "One and Only Utah"
        } ]
    )
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
