# frozen_string_literal: true
ENV["RAILS_ENV"] = "test"
require_relative "../../../../config/environment"
require "minitest/autorun"
require "minitest/mock"

class NoaaHourlyForecastTest < Minitest::Test
  def test_real_service_and_converter_preserve_summary_first_record_and_hourly_quantities
    service = Noaa::Forecast::HourlyForecast.new(40.5986, -111.5845)
    daily = { "name" => "Tonight", "number" => 1, "startTime" => "2026-10-11T18:00:00-06:00", "temperature" => 36, "temperatureUnit" => "F", "icon" => "https://example.test/icon?size=medium", "shortForecast" => "Clear", "detailedForecast" => "Clear tonight." }
    hourly = { "properties" => { "periods" => Array.new(120) { |index| daily.merge("name" => "", "number" => index + 1, "detailedForecast" => "", "probabilityOfPrecipitation" => { "value" => 0 }, "relativeHumidity" => { "value" => 70 }) } } }
    service.stub :noaa_response, { "properties" => { "forecastHourly" => "https://example.test/hourly" } } do
      service.stub :forecast_response, { "properties" => { "periods" => [daily] } } do
        service.stub :hourly_data, hourly do
          result = service.call
          assert result.success?
          periods = result.value.fetch("periods")
          assert_equal 99, periods.size
          assert_equal "Tonight", periods.first[:name]
          assert_equal "Clear tonight.", periods.first[:detailedForecast]
          assert_includes periods.first[:icon], "size=large"
          assert_nil periods.first[:probabilityOfPrecipitation][:value]
          assert_equal 0, periods[1][:probabilityOfPrecipitation][:value]
          assert_equal 70, periods[1][:relativeHumidity][:value]
          assert_equal "2026-10-11T18:00:00-06:00", periods[1][:startTime]
          assert_equal "Clear", periods[1][:detailedForecast]
        end
      end
    end
  end

  def test_missing_points_returns_failure
    service = Noaa::Forecast::HourlyForecast.new(40.5986, -111.5845)
    service.stub :noaa_response, nil do
      assert service.call.failure?
    end
  end

  def test_missing_hourly_response_returns_failure
    service = Noaa::Forecast::HourlyForecast.new(40.5986, -111.5845)
    service.stub :noaa_response, { "properties" => { "forecastHourly" => "https://example.test/hourly" } } do
      service.stub :forecast_response, { "properties" => { "periods" => [] } } do
        service.stub :hourly_data, nil do
          result = service.call
          assert result.failure?
          assert_includes result.value, "Unable to retrieve hourly forecasts"
        end
      end
    end
  end
end
