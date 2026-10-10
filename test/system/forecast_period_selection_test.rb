# frozen_string_literal: true

# The forecast page needs no database fixtures; keep this browser test independent.
ENV["RAILS_ENV"] = "test"
require_relative "../../config/environment"
require "minitest/autorun"
require "minitest/mock"
require "action_dispatch/system_test_case"

class ForecastPeriodSelectionTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ]

  def test_selection_uses_rendered_details_without_refetching
    period = {
      name: "Tonight", icon: nil, isDaytime: false, temperature: 36, temperatureUnit: "F",
      shortForecast: "Clear", detailedForecast: "Clear overnight.", windSpeed: "7 mph", windDirection: "W"
    }
    forecast_calls = 0
    discussion_calls = 0
    alert_calls = 0
    forecast = lambda do |*|
      forecast_calls += 1
      ServiceResult.new(success: true, value: { "forecasts" => [ period, period.merge(name: "Tomorrow", detailedForecast: "Rain tomorrow.") ] })
    end
    discussion = lambda do |*|
      discussion_calls += 1
      ServiceResult.new(success: true, value: { short_term: "Rain is approaching.", long_range: "Wet weather follows." })
    end

    alerts = lambda do |*|
      alert_calls += 1
      ServiceResult.new(success: true, value: { "alerts" => [] })
    end
    Weather::AlertsForecaster.stub :call, alerts do
      Weather::Forecaster.stub :call, forecast do
        Weather::DiscussionForecaster.stub :call, discussion do
          visit forecast_full_path(lat: "40.5986", long: "-111.5845", country_code: "us", location_name: "Brighton")
          assert_selector "#forecast-period-card-0[aria-pressed='true']"
          assert_selector "#forecast-period-detail-0", text: "Clear overnight."
          assert_no_selector "#forecast-period-detail-1"

          # Any network attempt caused by selection fails this test immediately.
          page.execute_script("window.fetch = () => { throw new Error('Unexpected fetch on card selection') }")
          find("#forecast-period-card-1").click
          assert_selector "#forecast-period-card-1[aria-pressed='true']"
          assert_selector "#forecast-period-detail-1", text: "Rain tomorrow."
          assert_no_selector "#forecast-period-detail-0"
          assert_equal 1, forecast_calls
          assert_equal 1, discussion_calls

          # Native button keyboard activation must switch the pre-rendered panel too.
          find("#forecast-period-card-0").send_keys(:enter)
          assert_selector "#forecast-period-detail-0", text: "Clear overnight."
          assert_equal 1, forecast_calls
          assert_equal 1, discussion_calls

          find("#forecast-tab-discussion").click
          assert_selector ".forecast-full-discussion", text: "Rain is approaching."
          assert_no_selector ".forecast-full-periods"
          find("#forecast-tab-discussion").send_keys(:arrow_right)
          assert_selector "#forecast-tab-alerts[aria-selected='true']"
          assert_selector ".forecast-full-alerts", text: "No active weather alerts."
          find("#forecast-tab-alerts").send_keys(:home)
          assert_selector "#forecast-tab-periods[aria-selected='true']"
          assert_selector "#forecast-period-card-0[aria-pressed='true']"
          find("#forecast-tab-periods").send_keys(:end)
          assert_selector "#forecast-tab-alerts[aria-selected='true']"
          find("#forecast-tab-alerts").send_keys(:arrow_left)
          assert_selector "#forecast-tab-discussion[aria-selected='true']"
          assert_equal 1, forecast_calls
          assert_equal 1, discussion_calls
          assert_equal 1, alert_calls

          page.driver.browser.manage.window.resize_to(390, 844)
          assert_selector ".forecast-full-discussion", text: "Rain is approaching."
          assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "The full page should not overflow the viewport"
        end
      end
    end
  end
end
