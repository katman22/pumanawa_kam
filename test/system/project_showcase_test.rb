require "test_helper"

if ENV["CHROMEDRIVER"].present?
  Selenium::WebDriver::Chrome::Service.driver_path = ENV.fetch("CHROMEDRIVER")
end

require "application_system_test_case"
require_relative "../helpers/whare_pumanawa_content_helper"

class ProjectShowcaseTest < ApplicationSystemTestCase
  include WharePumanawaContentHelper

  driven_by :selenium, using: :headless_chrome, screen_size: [ 1440, 1100 ] do |options|
    options.binary = ENV.fetch("CHROME_BINARY", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome") if Rails.root.to_s.start_with?("/Users/")
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "organization workspace leads to bounded project showcase and responsive resource actions" do
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
    organization = WharePumanawa::Organization.create!(name: "Studio A")
    project = organization.projects.create!(name: "Project A", description: "A project story")
    sibling = organization.projects.create!(name: "Sibling project")
    contributor = WharePumanawa::Contributor.create!(name: "Artist")
    mural = showcase_mural(contributor, title: "Project mural", photos: 2)
    mural.update!(project: project)
    other = showcase_mural(contributor, title: "Sibling mural")
    other.update!(project: sibling)
    admin = Admin::User.create!(username: "org-owner", password: "a-long-test-password", role: :organization_admin)
    organization.organization_memberships.create!(admin_user: admin)
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    visit admin_login_path
    fill_in "Username", with: admin.username
    fill_in "Password", with: "a-long-test-password"
    click_button "Sign in"
    click_link "View showcase"
    assert_current_path whare_pumanawa_organization_path(organization.slug, locale: :en)
    assert_selector "figcaption", text: "Project mural"
    assert_selector "figcaption", text: "Sibling mural"

    visit admin_whare_pumanawa_projects_path
    assert_action_below_table("New project")
    within "tbody tr", text: "Project A" do
      click_link "View showcase"
    end
    assert_current_path whare_pumanawa_project_path(project.slug, locale: :en)
    assert_selector "h1", text: "Project A"
    assert_selector ".showcase-art", count: 2
    assert_no_text "Sibling mural"
    assert_link "Studio A", href: whare_pumanawa_organization_path(organization.slug, locale: :en)
    assert_equal "grid", page.evaluate_script("getComputedStyle(document.querySelector('.showcase-wall')).display")
    image_width = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1];
      const image = document.querySelector('.showcase-art img');
      if (image.complete) done(image.naturalWidth);
      else {
        image.addEventListener('load', () => done(image.naturalWidth), { once: true });
        image.addEventListener('error', () => done(0), { once: true });
      }
    JS
    assert image_width.positive?, "The existing hero variant must load"
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    assert_equal "column", page.evaluate_script("getComputedStyle(document.querySelector('.showcase-wall')).flexDirection")
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    find(".showcase-art a", match: :first).click
    assert_current_path whare_pumanawa_mural_path(mural.slug, locale: :en)

    visit admin_root_path
    assert_link "View showcase"
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    click_button "Menu"
    click_link "Projects", exact: true
    assert_action_below_table("New project")
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    click_button "Menu"
    within "nav#admin-navigation" do
      click_link "Murals"
    end
    assert_action_below_table("New mural")
    assert_link "View portfolio"
    assert_link "Edit Project mural"
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
  end

  private

  def assert_action_below_table(label)
    link = find("a.btn.btn-primary", text: label, exact_text: true)
    assert page.evaluate_script("arguments[0].getBoundingClientRect().top >= document.querySelector('.table-responsive').getBoundingClientRect().bottom", link)
    assert page.evaluate_script("Math.abs(arguments[0].getBoundingClientRect().right - document.querySelector('main').getBoundingClientRect().right) < 2", link)
  end
end
