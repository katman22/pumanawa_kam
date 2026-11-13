require "test_helper"
require_relative "../helpers/weather_monitoring_data"

if ENV["CHROMEDRIVER"].present?
  Selenium::WebDriver::Chrome::Service.driver_path = ENV.fetch("CHROMEDRIVER")
end
require "application_system_test_case"

class AdminWeatherMonitoringTest < ApplicationSystemTestCase
  include WeatherMonitoringData
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1440, 1000 ] do |options|
    options.binary = ENV.fetch("CHROME_BINARY", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome") if Rails.root.to_s.start_with?("/Users/")
  end

  setup do
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
    Admin::User.create!(username: "weather-browser", password: "a-long-test-password", role: :canyon_admin)
    @resort = pilot_resort
    data = normalized
    @observation = WeatherMonitoring::RecordObservation.call(resort: @resort, normalized: data, snapshot: snapshot(data), fetched_at: ANCHOR).value[:observation]
    ResortWeatherMonitor.create!(resort: @resort, enabled: true, current_forecast_observation: @observation,
      mapping: fixture("brighton_points")["properties"], monitoring_level: "approaching", last_decision: { quality: "complete" },
      next_check_at: ANCHOR + 6.hours, next_probe_at: ANCHOR + 12.hours)
    HTTParty.stubs(:get).raises("Unexpected live NOAA call")
    visit admin_login_path
    fill_in "Username", with: "weather-browser"
    fill_in "Password", with: "a-long-test-password"
    click_button "Sign in"
    assert_selector ".admin-dashboard"
  end

  teardown { page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") }

  test "weather tabs preserve URLs browser history keyboard access and mobile layout" do
    visit admin_weather_monitoring_path
    within ".weather-tabs" do
      find_link("Alerts").send_keys(:enter)
    end
    assert_current_path admin_weather_monitoring_alerts_path(locale: :en)
    assert_selector ".weather-tabs a[aria-current='page']", text: "Alerts"
    assert_text "No geographic alert acquisition scopes are configured."
    assert_no_selector ".weather-tab-content form"
    page.refresh
    assert_selector ".weather-tabs a[aria-current='page']", text: "Alerts"
    within(".weather-tabs") { click_link "History" }
    assert_current_path admin_weather_monitoring_history_path(locale: :en)
    page.go_back
    assert_selector ".weather-tabs a[aria-current='page']", text: "Alerts"
    page.go_forward
    assert_selector ".weather-tabs a[aria-current='page']", text: "History"
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    click_link "Forecast snapshots"
    assert_selector "#forecast-history"
    assert_selector "#current-forecast .weather-snow-total", text: "4.2″"
    assert_no_selector ".weather-controls"
    within("nav[aria-label='Resort monitoring sections']") { click_link "Overview" }
    assert_selector ".weather-controls"
    click_link "Alerts", href: admin_weather_monitoring_alerts_path(locale: :en)
    assert_selector ".weather-tabs a[aria-current='page']", text: "Alerts"
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
  end

  test "Canyon monitor overview and evidence stay readable on desktop and mobile" do
    within "nav#admin-navigation" do
      click_link "Weather Monitoring"
    end
    assert_selector "body.admin-shell--canyon"
    assert_selector "[data-snowfall='current']", text: "4.2″"
    assert_equal "rgb(255, 255, 255)", page.evaluate_script("getComputedStyle(document.body).backgroundColor")
    click_link @resort.resort_name, exact: true
    within("nav[aria-label='Resort monitoring sections']") { click_link "Forecast Evidence" }
    assert_selector "tr[data-bucket='48-72']", text: "0–2.1″ (bounded)"
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    assert_selector "button.admin-menu-toggle[aria-expanded='false']"
    assert_no_selector "nav#admin-navigation"
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    assert_equal "1", page.evaluate_script("getComputedStyle(document.querySelector('.weather-facts')).gridTemplateColumns.split(' ').length.toString()")
    click_button "Menu"
    within "nav#admin-navigation" do
      assert_link "Weather Monitoring"
      assert_link "Canyon / Resorts"
      assert_no_link "Users"
      assert_no_link "Mahi Tahi / Organizations"
    end
    click_button "Menu"
    click_link "Inspect this forecast revision"
    assert_selector "h1", text: "Forecast revision"
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    assert_selector "details summary", text: "Raw selected intervals"
    within ".weather-monitoring" do
      assert_no_button "Save"
      assert_no_button "Delete"
    end
    visit admin_weather_monitoring_path
    assert_selector "[data-snowfall='current']", text: "4.2″"
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
  end

  test "resort tabs canonicalize legacy fragments and retain navigation controls and evidence" do
    visit admin_weather_monitoring_resort_path(@resort)
    assert_selector ".weather-tabs a[aria-current='page']", text: "Overview"
    assert_selector ".weather-controls"
    within("nav[aria-label='Resort monitoring sections']") { find_link("Forecast Evidence").send_keys(:enter) }
    assert_selector "section#forecast-history"
    assert_no_selector ".weather-controls"
    page.refresh
    assert_selector ".weather-tabs a[aria-current='page']", text: "Forecast Evidence"
    within("nav[aria-label='Resort monitoring sections']") { click_link "Decisions" }
    assert_selector "section#monitor-decision"
    page.go_back
    assert_selector ".weather-tabs a[aria-current='page']", text: "Forecast Evidence"
    page.go_forward
    assert_selector ".weather-tabs a[aria-current='page']", text: "Decisions"
    { "forecast-history" => [ "evidence", "Forecast Evidence" ], "monitor-decision" => [ "decisions", "Decisions" ],
      "alert-history" => [ "alerts", "Alert History" ], "current-forecast" => [ "evidence", "Forecast Evidence" ] }.each do |anchor, (tab, label)|
      visit admin_weather_monitoring_resort_path(@resort, anchor: anchor)
      assert_selector ".weather-tabs a[aria-current='page']", text: label
      assert_selector "section##{anchor}"
      assert_equal tab, URI.decode_www_form(URI(page.current_url).query).to_h["tab"]
    end
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    within("nav[aria-label='Resort monitoring sections']") { click_link "Alert History" }
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    within("nav[aria-label='Resort monitoring sections']") { click_link "Forecast Evidence" }
    click_link "Inspect this forecast revision"
    assert_selector "h1", text: "Forecast revision"
    click_link "Back to #{@resort.resort_name} monitoring"
    assert_selector ".weather-tabs a[aria-current='page']", text: "Forecast Evidence"
    assert_selector "section#forecast-history"
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
  end

  test "legacy evidence fragments provide visible native links without JavaScript" do
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: true)
    visit admin_weather_monitoring_resort_path(@resort, anchor: "forecast-history")
    find("noscript a#forecast-history").click
    assert_selector "section#forecast-history"
    assert_selector ".weather-tabs a[aria-current='page']", text: "Forecast Evidence"
  ensure
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: false)
  end
end
