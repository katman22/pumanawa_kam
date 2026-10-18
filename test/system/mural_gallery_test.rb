require "test_helper"

if ENV["CHROMEDRIVER"].present?
  Selenium::WebDriver::Chrome::Service.driver_path = ENV.fetch("CHROMEDRIVER")
end

require "application_system_test_case"

class MuralGalleryTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1440, 1000 ] do |options|
    options.binary = ENV.fetch("CHROME_BINARY", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome") if Rails.root.to_s.start_with?("/Users/")
  end

  setup do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    @murals = 4.times.map do |index|
      mural = WharePumanawa::Mural.create!(title: "Artwork #{index + 1}", position: index,
        location: "Community wall", year: 2026, client: "Local community", description: "A story painted together.\n\nColour, place and connection.")
      photo = mural.mural_photos.build(alt_text: "Painted landscape #{index + 1}")
      photo.image.attach(io: File.open(file_fixture("mural.png")), filename: "mural.png", content_type: "image/png")
      photo.save!
      mural.update!(published: true)
      mural
    end
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "local selection keyboard navigation and mobile layout need no requests" do
    visit whare_pumanawa_murals_path
    assert_selector ".whare-panel:not([hidden]) h2", text: "Artwork 1"
    # Wait for initial eager image delivery, including the hidden panels.
    page.document.synchronize(errors: [ Minitest::Assertion ]) do
      assert page.evaluate_script("Array.from(document.querySelectorAll('.whare-gallery img')).every(image => image.complete && image.naturalWidth > 0)")
    end
    page.execute_script("performance.clearResourceTimings()")
    find("#whare-selector-#{@murals[1].id}").click
    assert_selector ".whare-panel:not([hidden]) h2", text: "Artwork 2"
    find("#whare-selector-#{@murals[1].id}").send_keys(:arrow_right)
    assert_selector ".whare-panel:not([hidden]) h2", text: "Artwork 3"
    assert_selector "#whare-selector-#{@murals[2].id}:focus[aria-pressed='true'][tabindex='0']"
    find("#whare-selector-#{@murals[2].id}").send_keys(:end)
    assert_selector ".whare-panel:not([hidden]) h2", text: "Artwork 4"
    find("#whare-selector-#{@murals[3].id}").send_keys(:home)
    assert_selector ".whare-panel:not([hidden]) h2", text: "Artwork 1"
    find("#whare-selector-#{@murals[0].id}").send_keys(:arrow_left)
    assert_selector ".whare-panel:not([hidden]) h2", text: "Artwork 4"
    assert_empty page.evaluate_script("performance.getEntriesByType('resource').map(entry => entry.name)")
    page.save_screenshot(Rails.root.join("tmp/screenshots/mural-gallery-desktop.png"))
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    assert page.evaluate_script("document.querySelector('.whare-selector-strip').scrollWidth > document.querySelector('.whare-selector-strip').clientWidth")
    assert page.evaluate_script("document.querySelector('.whare-selector').getBoundingClientRect().height >= 44")
    page.save_screenshot(Rails.root.join("tmp/screenshots/mural-gallery-mobile.png"))
    visit whare_pumanawa_mural_path(@murals[2].slug)
    assert_selector ".whare-panel:not([hidden]) h2", text: "Artwork 3"
  end

  test "mural admin can create upload describe and publish through ordinary forms" do
    WharePumanawa::Contributor.create!(name: "Community artist")
    project = WharePumanawa::Project.create!(name: "Community collection")
    admin = Admin::User.create!(username: "artist", password: "a-long-test-password", role: :mural_admin)
    project.project_memberships.create!(admin_user: admin)
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
    visit admin_login_path
    fill_in "Username", with: "artist"
    fill_in "Password", with: "a-long-test-password"
    click_button "Sign in"
    click_link "Projects", match: :first
    click_link "Community collection"
    click_link "New mural in this project"
    fill_in "Title", with: "Community wall"
    select "Community artist", from: "Contributor"
    click_button "Save mural"
    assert_text "Mural created"
    attach_file "JPEG, PNG or WebP images (up to 20 MiB each)", file_fixture("mural-small.jpg")
    fill_in "Initial alt text for these photographs", with: "Heron painted on a community wall"
    click_button "Upload photographs"
    assert_text "Photos added"
    check "Published — visible in the public portfolio"
    click_button "Save mural"
    assert_text "Mural updated"
    click_link "Open public permalink"
    assert_selector ".whare-panel:not([hidden]) h2", text: "Community wall"
    assert_selector ".whare-hero[alt='Heron painted on a community wall']"
  end
end
