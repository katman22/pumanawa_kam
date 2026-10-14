# frozen_string_literal: true
ENV["RAILS_ENV"] = "test"
require_relative "../../../../config/environment"
require "minitest/autorun"
require "minitest/mock"

class HourlyAlertsCacheTest < Minitest::Test
  def setup
    @original_configuration = %w[OPENWEATHER_API_KEY OPENWEATHER_ONE_CALL_API].to_h { |key| [key, ENV[key]] }
    ENV["OPENWEATHER_API_KEY"] = "test-openweather-key"
    ENV["OPENWEATHER_ONE_CALL_API"] = "https://weather.example.test/onecall"
  end

  def teardown
    @original_configuration.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  Response = Struct.new(:body) do
    def [](_key)
      nil
    end
  end

  def test_alerts_then_hourly_have_independent_cached_payloads
    assert_independent_cache([:alerts, :hourly])
  end

  def test_hourly_then_alerts_have_independent_cached_payloads
    assert_independent_cache([:hourly, :alerts])
  end

  private

  def assert_independent_cache(order)
    store = ActiveSupport::Cache::MemoryStore.new
    calls = []
    request = lambda do |url, options|
      query = options.fetch(:query)
      assert_equal "test-openweather-key", query[:appid]
      calls << [url, query[:exclude]]
      payload = if url.end_with?("/overview")
        { "weather_overview" => "Overview text" }
      elsif query.fetch(:exclude).include?("hourly")
        { "alerts" => [{ "event" => "Wind warning", "description" => "Strong winds", "start" => 1_791_720_000, "end" => 1_791_723_600 }] }
      else
        { "hourly" => [{ "dt" => 1_791_720_000, "temp" => 0, "wind_speed" => 2, "wind_deg" => 90, "humidity" => 70, "pop" => 0.25, "weather" => [{ "main" => "Rain", "icon" => "10d" }] }] }
      end
      Response.new(JSON.generate(payload))
    end
    services = {
      alerts: -> { OpenWeather::Forecast::Alerts.new(latitude: 40.5986, longitude: -111.5845).call },
      hourly: -> { OpenWeather::Forecast::Hourly.new(latitude: 40.5986, longitude: -111.5845).call }
    }
    Rails.stub :cache, store do
      HTTParty.stub :get, request do
        2.times do
          order.each do |kind|
            result = services.fetch(kind).call
            assert result.success?
            if kind == :alerts
              assert_equal "Wind warning", result.value.fetch("alerts").first[:event]
            else
              period = result.value.first
              assert_equal "Rain", period[:shortForecast]
              assert_equal 0, period[:temperature]
              assert_equal 25, period[:probabilityOfPrecipitation][:value]
              assert_equal 70, period[:relativeHumidity][:value]
            end
          end
        end
      end
    end
    assert_equal 3, calls.size, "Each payload and overview should be fetched once, then reused"
    assert_equal 1, calls.count { |url, _| url.end_with?("/overview") }
    assert_equal 1, calls.count { |_, exclude| exclude == "minutely, daily, current, hourly" }
    assert_equal 1, calls.count { |_, exclude| exclude == "minutely, daily, current, alerts" }
  end
end
