require "test_helper"
require "vips"

if ENV["CHROMEDRIVER"].present?
  Selenium::WebDriver::Chrome::Service.driver_path = ENV.fetch("CHROMEDRIVER")
end

require "application_system_test_case"

class ContributorShowcaseTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1440, 1100 ] do |options|
    options.binary = ENV.fetch("CHROME_BINARY", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome") if Rails.root.to_s.start_with?("/Users/")
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "mixed orientations form a desktop exhibition wall and a mobile editorial stack" do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    contributor = WharePumanawa::Contributor.create!(name: "Community artist", bio: "Painting stories of place and connection.", location: "Aotearoa")
    mural = contributor.murals.create!(title: "Our wall", description: "A shared story across colour and place.")
    landscape = Vips::Image.new_from_file(file_fixture("mural.png").to_s)
    sources = [ landscape, landscape.rot(:d90), landscape.crop(0, 0, 800, 800) ]
    8.times do |index|
      photo = mural.mural_photos.build(alt_text: "Painted colours #{index + 1}", position: index)
      photo.image.attach(io: StringIO.new(sources[index % 3].write_to_buffer(".png")), filename: "photo-#{index}.png", content_type: "image/png")
      photo.save!
      photo.image.analyze
    end
    mural.update!(published: true)
    visit whare_pumanawa_contributor_path(contributor.slug)
    assert_selector ".showcase-wall--large .showcase-art", count: 8
    assert_selector "[data-orientation=portrait]"
    assert_selector "[data-orientation=landscape]"
    assert_selector "[data-orientation=squareish]"
    assert_equal "grid", page.evaluate_script("getComputedStyle(document.querySelector('.showcase-wall')).display")
    assert page.evaluate_script("Array.from(document.querySelectorAll('.showcase-art img')).every(image => getComputedStyle(image).objectFit === 'contain')")
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    page.save_screenshot(Rails.root.join("tmp/screenshots/contributor-showcase-desktop.png"))
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    assert_equal "column", page.evaluate_script("getComputedStyle(document.querySelector('.showcase-wall')).flexDirection")
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    assert page.evaluate_script("document.querySelector('.showcase-art').getBoundingClientRect().width > 300")
    assert_selector ".showcase-bio", text: /Painting stories/
    page.save_screenshot(Rails.root.join("tmp/screenshots/contributor-showcase-mobile.png"))
    find(".showcase-art a", match: :first).click
    assert_selector ".whare-panel:not([hidden]) h2", text: "Our wall"
    assert_selector ".whare-contributor a", text: "Community artist"
  end
end
