# frozen_string_literal: true
ENV["RAILS_ENV"] = "test"
require_relative "../../config/environment"
require "minitest/autorun"
require "minitest/mock"
require "action_dispatch/system_test_case"

class DualForecastSelectionTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1000]

  def test_independent_period_selection_and_failure_preserve_other_side
    period = { name: "Tonight", detailedForecast: "Clear overnight.", temperature: 36, temperatureUnit: "F", shortForecast: "Clear" }
    calls = 0
    geocoder = ->(*) { ServiceResult.new(success: true, value: [{ name: "Brighton", lat: 40.5986, lng: -111.5845, country_code: "us" }]) }
    forecast = lambda do |*|
      calls += 1
      ServiceResult.new(success: true, value: { "forecasts" => [period, period.merge(name: "Tomorrow", detailedForecast: "Rain tomorrow.")] })
    end
    Google::GeoLocate.stub :call, geocoder do
      Weather::Forecaster.stub :call, forecast do
        visit forecast_dual_path
        fill_in "Location", with: "Brighton"
        click_button "Load Location A"
        assert_selector "#dual-a-period-card-0[aria-pressed='true']"
        click_button "Load Location B"
        assert_selector "#dual-b-period-card-0[aria-pressed='true']"
        assert_equal 2, calls
        ids = page.evaluate_script("Array.from(document.querySelectorAll('[id]'), element => element.id)")
        assert_equal ids.uniq, ids, "DOM IDs must be unique across both locations"
        page.execute_script("window.dualTestFetch = window.fetch; window.fetch = () => { throw new Error('Unexpected fetch on period selection') }")
        find("#dual-a-period-card-1").click
        assert_selector "#dual-a-period-detail-1", text: "Rain tomorrow."
        assert_selector "#dual-b-period-detail-0", text: "Clear overnight."
        find("#dual-b-period-card-1").send_keys(:enter)
        assert_selector "#dual-b-period-detail-1", text: "Rain tomorrow."
        assert_equal 2, calls
        page.execute_script("window.fetch = window.dualTestFetch; delete window.dualTestFetch")
        Weather::Forecaster.stub :call, ServiceResult.new(success: false, value: "Unavailable") do
          click_button "Load Location B"
          assert_selector "#location_response_b [role='alert']", text: "Unavailable"
          assert_selector "#dual-a-period-detail-1", text: "Rain tomorrow."
        end
        page.driver.browser.manage.window.resize_to(390, 844)
        assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
      end
    end
  end
end
