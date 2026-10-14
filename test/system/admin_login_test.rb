require "test_helper"

# Optional local driver override avoids the legacy webdrivers downloader.
if ENV["CHROMEDRIVER"].present?
  Selenium::WebDriver::Chrome::Service.driver_path = ENV.fetch("CHROMEDRIVER")
end

require "application_system_test_case"

class AdminLoginTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1440, 1000 ] do |options|
    options.binary = ENV.fetch("CHROME_BINARY", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome") if Rails.root.to_s.start_with?("/Users/")
  end

  setup do
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
  end

  test "form signs in and out without image rotation" do
    Admin::User.create!(username: "artist", password: "a-long-test-password")
    visit admin_login_path
    image = find(".entry-image")["src"]
    fill_in "Username", with: "artist"
    fill_in "Password", with: "a-long-test-password"
    assert_equal image, find(".entry-image")["src"]
    click_button "Sign in"
    assert_current_path admin_root_path(locale: :en)
    click_button "Sign out"
    assert_current_path admin_login_path(locale: :en)
    visit admin_root_path
    assert_current_path admin_login_path(locale: :en)
  end

  test "desktop and mobile preserve landscape and portrait composition" do
    visit admin_login_path
    assert_equal "contain", page.evaluate_script("getComputedStyle(document.querySelector('.entry-image')).objectFit")
    assert page.evaluate_script("document.querySelector('.entry-artwork').getBoundingClientRect().right < document.querySelector('.entry-login').getBoundingClientRect().left")
    Admin::SessionsController::ARTWORK.each do |filename|
      source = ActionController::Base.helpers.asset_path("admin_splash/#{filename}")
      dimensions = page.evaluate_async_script(<<~JS, source)
        const image = document.querySelector('.entry-image');
        const done = arguments[arguments.length - 1];
        image.onload = () => done([image.naturalWidth, image.naturalHeight]);
        image.onerror = () => done([0, 0]);
        image.src = arguments[0];
      JS
      assert dimensions.all?(&:positive?), "Artwork did not load: #{filename}"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/admin-splash-desktop.png"))
    # Synthetic portrait source exercises layout; it is not part of the curated pool.
    page.execute_script(%q{document.querySelector('.entry-image').src = 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" width="400" height="800"><rect width="400" height="800" fill="%238c2426"/></svg>'})
    assert_equal "contain", page.evaluate_script("getComputedStyle(document.querySelector('.entry-image')).objectFit")
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 820, height: 1180, deviceScaleFactor: 1, mobile: false)
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    assert_equal 390, page.evaluate_script("innerWidth")
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    assert page.evaluate_script("document.querySelector('.entry-artwork').getBoundingClientRect().bottom <= document.querySelector('.entry-login').getBoundingClientRect().top")
    assert page.evaluate_script("document.querySelector('input[type=submit]').getBoundingClientRect().bottom < innerHeight")
    assert page.evaluate_script("document.querySelector('input[type=password]').getBoundingClientRect().height >= 44")
    page.save_screenshot(Rails.root.join("tmp/screenshots/admin-splash-mobile-portrait.png"))
    source = ActionController::Base.helpers.asset_path("admin_splash/IMG_6377.JPG")
    page.evaluate_async_script(<<~JS, source)
      const image = document.querySelector('.entry-image');
      const done = arguments[arguments.length - 1];
      image.onload = () => done(true);
      image.src = arguments[0];
    JS
    page.save_screenshot(Rails.root.join("tmp/screenshots/admin-splash-mobile-landscape.png"))
  end
end
