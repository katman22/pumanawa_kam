require "test_helper"

if ENV["CHROMEDRIVER"].present?
  Selenium::WebDriver::Chrome::Service.driver_path = ENV.fetch("CHROMEDRIVER")
end

require "application_system_test_case"

class AdminNavigationTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1440, 1000 ] do |options|
    options.binary = ENV.fetch("CHROME_BINARY", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome") if Rails.root.to_s.start_with?("/Users/")
  end

  setup do
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
    Admin::User.create!(username: "shell-owner", password: "a-long-test-password", role: :super_admin)
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    visit admin_login_path
    fill_in "Username", with: "shell-owner"
    fill_in "Password", with: "a-long-test-password"
    click_button "Sign in"
    assert_selector ".admin-dashboard"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "desktop and mobile navigation toggle accessibly and switch resource themes" do
    assert_selector "nav#admin-navigation"
    assert_no_button "Menu"
    assert_equal "row", page.evaluate_script("getComputedStyle(document.querySelector('.admin-nav')).flexDirection")
    assert_equal "rgb(250, 249, 246)", page.evaluate_script("getComputedStyle(document.body).backgroundColor")

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    assert_selector "button.admin-menu-toggle[aria-expanded='false']"
    assert_no_selector "nav#admin-navigation"
    click_button "Menu"
    assert_selector "button.admin-menu-toggle[aria-expanded='true']"
    within "nav#admin-navigation" do
      assert_link "Dashboard"
      assert_link "Canyon / Resorts"
      assert_link "Mahi Tahi / Organizations"
      assert_link "Projects"
      assert_link "Contributors"
      assert_link "Murals"
      assert_link "Users"
      assert_button "Sign out"
    end
    find("nav a", text: "Dashboard", exact_text: true).send_keys(:escape)
    assert_no_selector "nav#admin-navigation"
    assert_equal "Menu", page.evaluate_script("document.activeElement.textContent.trim().replace('☰', '').trim()")
    click_button "Menu"
    click_button "Menu"
    assert_selector "button.admin-menu-toggle[aria-expanded='false']"
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")

    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    assert_no_button "Menu"
    assert_selector "nav#admin-navigation"
    click_link "Canyon / Resorts"
    assert_selector "body.admin-shell--canyon"
    assert_equal "rgb(13, 110, 253)", page.evaluate_script("getComputedStyle(document.querySelector('.btn-primary')).backgroundColor")
    click_link "Dashboard"
    assert_selector "body.admin-shell--default"
    click_link "Users", exact: true
    assert_selector "body.admin-shell--default"
    click_link "Mahi Tahi / Organizations"
    assert_selector "body.admin-shell--default"
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    assert_selector "button.admin-menu-toggle[aria-expanded='false']"
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    click_button "Menu"
    click_button "Sign out"
    assert_current_path admin_login_path(locale: :en)
  end
end
