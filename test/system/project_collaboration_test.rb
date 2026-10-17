require "test_helper"

if ENV["CHROMEDRIVER"].present?
  Selenium::WebDriver::Chrome::Service.driver_path = ENV.fetch("CHROMEDRIVER")
end

require "application_system_test_case"

class ProjectCollaborationTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1100 ] do |options|
    options.binary = ENV.fetch("CHROME_BINARY", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome") if Rails.root.to_s.start_with?("/Users/")
  end

  test "super admin sets up collaboration then member uploads publishes and cannot open another project" do
    Admin::User.create!(username: "owner", password: "a-long-test-password", role: :super_admin)
    Admin::User.create!(username: "artist", password: "a-long-test-password", role: :mural_admin)
    contributor = WharePumanawa::Contributor.create!(name: "Community artist")
    other = WharePumanawa::Project.create!(name: "Private collaboration")
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
    visit admin_login_path
    fill_in "Username", with: "owner"
    fill_in "Password", with: "a-long-test-password"
    click_button "Sign in"
    click_link "Whare Pūmanawa / Projects"
    click_link "New project"
    fill_in "Name", with: "Community collaboration"
    fill_in "Description (plain text)", with: "Painting together"
    click_button "Save project"
    assert_text "Project created"
    select "artist", from: "Add mural administrator"
    click_button "Add member"
    assert_text "Project member added"
    click_link "New mural in this project"
    assert_selector "select[name='whare_pumanawa_mural[project_id]'] option[selected]", text: "Community collaboration"
    select contributor.name, from: "Contributor"
    fill_in "Title", with: "Shared wall"
    click_button "Save mural"
    assert_text "Mural created"
    click_button "Sign out"
    fill_in "Username", with: "artist"
    fill_in "Password", with: "a-long-test-password"
    click_button "Sign in"
    click_link "Whare Pūmanawa / Projects"
    assert_link "Community collaboration"
    assert_no_link "Private collaboration"
    click_link "Community collaboration"
    click_link "Shared wall"
    fill_in "Title", with: "Our shared wall"
    click_button "Save mural"
    assert_text "Mural updated"
    attach_file "JPEG, PNG or WebP images (up to 20 MiB each)", file_fixture("mural.png")
    fill_in "Initial alt text for these photographs", with: "Community mural in bright colours"
    click_button "Upload photographs"
    assert_text "Photos added"
    check "Published — visible in the public portfolio"
    click_button "Save mural"
    assert_text "Mural updated"
    click_link "Open public permalink"
    assert_selector ".whare-panel:not([hidden]) h2", text: "Our shared wall"
    assert_selector ".whare-hero[alt='Community mural in bright colours']"
    assert_link "Community artist"
    status = page.evaluate_async_script(<<~JS, admin_whare_pumanawa_project_path(other))
      const done = arguments[arguments.length - 1];
      fetch(arguments[0]).then(response => done(response.status)).catch(() => done(0));
    JS
    assert_equal 403, status
    visit admin_whare_pumanawa_project_path(other)
    assert_no_text "Private collaboration"
  end
end
