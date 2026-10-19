require "test_helper"

if ENV["CHROMEDRIVER"].present?
  Selenium::WebDriver::Chrome::Service.driver_path = ENV.fetch("CHROMEDRIVER")
end

require "application_system_test_case"
require_relative "../helpers/whare_pumanawa_content_helper"

class OrganizationShowcaseTest < ApplicationSystemTestCase
  include WharePumanawaContentHelper

  driven_by :selenium, using: :headless_chrome, screen_size: [ 1440, 1100 ] do |options|
    options.binary = ENV.fetch("CHROME_BINARY", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome") if Rails.root.to_s.start_with?("/Users/")
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "owner creates an organization body of work and member sees only their organization context" do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    Admin::User.create!(username: "owner", password: "a-long-test-password", role: :super_admin)
    Admin::User.create!(username: "artist", password: "a-long-test-password", role: :mural_admin)
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
    visit admin_login_path
    fill_in "Username", with: "owner"
    fill_in "Password", with: "a-long-test-password"
    click_button "Sign in"
    click_link "Mahi Tahi / Organizations"
    click_link "New organization"
    fill_in "Name", with: "Studio A"
    fill_in "Description (plain text)", with: "Stories made with our community."
    fill_in "Location", with: "Aotearoa"
    click_button "Save organization"
    assert_text "Organization created"
    organization = WharePumanawa::Organization.find_by!(name: "Studio A")
    click_link "Contributors", match: :first
    click_link "New contributor"
    fill_in "Name", with: "Artist A"
    click_button "Save contributor"
    visit admin_whare_pumanawa_organization_path(organization)
    within "form[action*='/organization_contributors']" do
      select "Artist A", from: "organization_contributor_contributor_id"
      find("input[type='submit']").click
    end
    assert_text "Contributor associated"
    click_link "New project in this organization"
    fill_in "Name", with: "Project A"
    click_button "Save project"
    select "artist", from: "Add mural administrator"
    click_button "Add member"
    click_link "New mural in this project"
    select "Artist A", from: "Contributor"
    fill_in "Title", with: "Mural A"
    fill_in "Story / description (plain text)", with: "A story from our studio."
    click_button "Save mural"
    attach_file "JPEG, PNG or WebP images (up to 20 MiB each)", file_fixture("mural.png")
    fill_in "Initial alt text for these photographs", with: "Studio A painted colours"
    click_button "Upload photographs"
    assert_text "Photos added"
    check "Published — visible in the public portfolio"
    click_button "Save mural"
    assert_text "Mural updated"
    other = WharePumanawa::Organization.create!(name: "Studio B")
    project_b = other.projects.create!(name: "Project B")
    # The same credited contributor in both organizations must not widen ownership.
    contributor = WharePumanawa::Contributor.find_by!(name: "Artist A")
    other.organization_contributors.create!(contributor: contributor)
    foreign = showcase_mural(contributor, title: "Mural B")
    foreign.update!(project: project_b)
    visit whare_pumanawa_root_path
    assert_selector "h1", text: "Organizations"
    assert_no_selector ".showcase-art, .whare-selector"
    click_link "Studio A"
    assert_selector ".showcase-art figcaption", text: "Mural A"
    image_width = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1];
      const image = document.querySelector('.showcase-art img');
      if (image.complete) done(image.naturalWidth);
      else {
        image.addEventListener('load', () => done(image.naturalWidth), { once: true });
        image.addEventListener('error', () => done(0), { once: true });
      }
    JS
    assert image_width.positive?, "The processed organization image must load"
    assert_no_text "Mural B"
    assert_no_text "Project B"
    assert_link "Artist A"
    assert_text "Project A"
    page.save_screenshot(Rails.root.join("tmp/screenshots/organization-showcase-desktop.png"))
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    assert_equal "column", page.evaluate_script("getComputedStyle(document.querySelector('.showcase-wall')).flexDirection")
    page.save_screenshot(Rails.root.join("tmp/screenshots/organization-showcase-mobile.png"))
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    visit admin_root_path
    click_button "Sign out"
    fill_in "Username", with: "artist"
    fill_in "Password", with: "a-long-test-password"
    click_button "Sign in"
    click_link "Mahi Tahi / Organizations"
    assert_link "Studio A"
    assert_no_link "Studio B"
    click_link "Studio A"
    assert_no_link "Edit organization"
    assert_no_button "Associate contributor"
    assert_link "Project A"
    status = page.evaluate_async_script(<<~JS, admin_whare_pumanawa_organization_path(other))
      const done = arguments[arguments.length - 1];
      fetch(arguments[0]).then(response => done(response.status)).catch(() => done(0));
    JS
    assert_equal 403, status
  end
end
