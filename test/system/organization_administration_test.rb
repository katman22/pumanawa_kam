require "test_helper"

if ENV["CHROMEDRIVER"].present?
  Selenium::WebDriver::Chrome::Service.driver_path = ENV.fetch("CHROMEDRIVER")
end

require "application_system_test_case"

class OrganizationAdministrationTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1440, 1100 ] do |options|
    options.binary = ENV.fetch("CHROME_BINARY", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome") if Rails.root.to_s.start_with?("/Users/")
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "owner assigns an organization administrator who manages a workspace and real images" do
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
    Admin::User.create!(username: "owner", password: "a-long-test-password", role: :super_admin)
    foreign = WharePumanawa::Organization.create!(name: "Private Studio B")
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    sign_in("owner")
    click_link "Mahi Tahi / Organizations"
    click_link "New organization"
    fill_in "Name", with: "Studio A"
    click_button "Save organization"
    assert_text "Organization created"
    organization = WharePumanawa::Organization.find_by!(name: "Studio A")
    click_link "Users", exact: true
    click_link "New administrator"
    fill_in "Username", with: "org-owner"
    select "Organization admin", from: "Role"
    fill_in "Password", with: "a-long-test-password", exact: true
    fill_in "Password confirmation", with: "a-long-test-password"
    find("input[type='submit']").click
    assert_text "Administrator created"
    visit admin_whare_pumanawa_organization_path(organization)
    select "org-owner", from: "Add organization admin"
    click_button "Add organization admin"
    assert_text "Organization admin added"
    click_button "Sign out"

    sign_in("org-owner")
    assert_current_path admin_root_path(locale: :en)
    assert_selector "#organization-workspace-heading", text: "Studio A"
    assert_no_link "Users"
    assert_no_link "Canyon / Resorts"
    assert_no_text foreign.name
    click_link "Add contributor"
    fill_in "Name", with: "Artist A"
    click_button "Save contributor"
    assert_text "Contributor created"
    click_link "Dashboard", exact: true
    click_link "New project", exact: true
    fill_in "Name", with: "Project A"
    fill_in "Description (plain text)", with: "Our project story"
    click_button "Save project"
    assert_text "Project created"
    project = organization.projects.find_by!(name: "Project A")
    assert_empty project.project_memberships
    click_link "New mural in this project"
    select "Artist A", from: "Contributor"
    fill_in "Title", with: "Mural A"
    fill_in "Story / description (plain text)", with: "Our mural story"
    click_button "Save mural"
    attach_file "JPEG, PNG or WebP images (up to 20 MiB each)", file_fixture("mural.png")
    fill_in "Initial alt text for these photographs", with: "Heron painted on a community wall"
    click_button "Upload photographs"
    assert_text "Photos added"
    assert_selector "img[width='120']"
    fill_in "Story / description (plain text)", with: "Our updated mural story"
    check "Published — visible in the public portfolio"
    click_button "Save mural"
    assert_text "Mural updated"
    mural = project.murals.find_by!(title: "Mural A")
    visit whare_pumanawa_mural_path(mural.slug)
    assert_selector ".whare-panel:not([hidden]) h2", text: "Mural A"
    assert_text "Our updated mural story"
    visit edit_admin_whare_pumanawa_mural_path(mural)
    uncheck "Published — visible in the public portfolio"
    click_button "Save mural"
    accept_confirm { click_button "Remove photo" }
    assert_text "Photo removed"
    accept_confirm { click_button "Delete mural" }
    assert_text "Mural deleted"
    visit admin_whare_pumanawa_organization_path(foreign)
    assert_no_text foreign.name
    visit admin_root_path
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    click_button "Menu"
    within "nav#admin-navigation" do
      assert_link "Mahi Tahi / Studio A"
      assert_link "Projects"
      assert_link "Contributors"
      assert_link "Murals"
      assert_no_link "Users"
      assert_no_link "Canyon / Resorts"
      assert_button "Sign out"
    end
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    click_button "Sign out"
    assert_current_path admin_login_path(locale: :en)
  end

  private

  def sign_in(username)
    visit admin_login_path
    fill_in "Username", with: username
    fill_in "Password", with: "a-long-test-password"
    click_button "Sign in"
  end
end
