# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
module Noaa
  module Forecast
    class SummaryTest < ActiveSupport::TestCase
      test "Receive valid response from api" do
        result = { "number"=>1,
                  "name"=>"This Afternoon",
                  "startTime"=>"2025-04-10T15:00:00-05:00",
                  "endTime"=>"2025-04-10T18:00:00-05:00",
                  "isDaytime"=>true,
                  "temperature"=>70,
                  "temperatureUnit"=>"F",
                  "temperatureTrend"=>"",
                  "probabilityOfPrecipitation"=>{ "unitCode"=>"wmoUnit:percent", "value"=>nil },
                  "windSpeed"=>"15 to 20 mph",
                  "windDirection"=>"NW",
                  "icon"=>"https://api.weather.gov/icons/land/day/few?size=medium",
                  "shortForecast"=>"Sunny",
                  "detailedForecast"=>"Sunny, with a high near 70. Northwest wind 15 to 20 mph, with gusts as high as 30 mph." }

        latitude, longitude, zipcode = [ 39.4225192, -111.714358, 22340 ]
        success_response = Minitest::Mock.new
        success_response.expect :success?, true
        success_response.expect :value, result
        Noaa::Forecast::Summary.stub :call, success_response do
          result = Noaa::Forecast::Summary.call(latitude, longitude, zipcode)
          assert result.success?
        end
      end

      test "Receive in-valid response from noaa api" do
        latitude, longitude, zipcode = [ 39.4225192, -111.714358, 22340 ]
        failure_response = Minitest::Mock.new
        failure_response.expect :failure?, true
        failure_response.expect :value, "No forecast for location found"
        Noaa::Forecast::Summary.stub :call, failure_response do
          result = Noaa::Forecast::Summary.call(latitude, longitude, zipcode)
          assert result.failure?
        end
      end
    end
  end
end
