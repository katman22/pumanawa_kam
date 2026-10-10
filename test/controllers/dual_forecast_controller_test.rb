# frozen_string_literal: true
ENV["RAILS_ENV"] = "test"
require_relative "../../config/environment"
require "minitest/autorun"
require "minitest/mock"

class DualForecastControllerTest < ActionDispatch::IntegrationTest
  def setup
    @location = { name: "Brighton", lat: 40.5986, lng: -111.5845, country_code: "us" }
    @period = { name: "Tonight", temperature: 36, temperatureUnit: "F", shortForecast: "Clear", detailedForecast: "Clear overnight." }
  end

  def test_shell_has_header_navigation_and_independent_frames
    get forecast_dual_path
    assert_response :success
    assert_select ".forecast-full-header h1", "Dual Forecast"
    assert_select "figcaption", count: 1
    assert_select "nav a", text: "Find Another Forecast"
    assert_select "button[value='Locale A']", text: "Load Location A"
    assert_select "button[value='Locale B']", text: "Load Location B"
    %w[a b].each { |side| assert_select "turbo-frame#location_response_#{side}", count: 1 }
    assert_select ".forecast-full-header a", text: "Dual Screen Forecasts", count: 0
  end

  def test_one_result_loads_each_side_with_noaa_and_stores_resolved_recent
    %w[a b].each do |side|
      calls = []
      search(side, [@location], forecast: ->(*args) { calls << args; success(@period) })
      assert_equal [["noaa", 40.5986, -111.5845]], calls
      assert_target(side)
      assert_select "#dual-#{side}-period-card-0[aria-controls='dual-#{side}-period-detail-0']", count: 1
      assert_select "#dual-#{side}-period-detail-0[aria-labelledby='dual-#{side}-period-title-0']", text: /Clear overnight/
    end
    get forecast_dual_path
    assert_select ".forecast-dual-recent button[data-lat='40.5986'][data-lng='-111.5845']", text: "Brighton", count: 1
  end

  def test_zero_results_and_geocoder_failure_are_side_specific
    search("a", [])
    assert_target("a")
    assert_select "turbo-frame p", text: /No locations found/
    search("b", [], geo_success: false)
    assert_target("b")
    assert_select "[role='alert']", text: /Location search is currently unavailable/
  end

  def test_each_sides_full_forecast_and_radar_links_preserve_its_location
    { "a" => @location, "b" => { name: "Queenstown", lat: -45.03, lng: 168.66, country_code: "nz" } }.each do |side, location|
      search(side, [location], forecast: ->(*) { location[:country_code] == "us" ? success(@period) : ServiceResult.new(success: true, value: [@period]) })
      assert_select "#location_response_#{side} .forecast-dual-links a[data-turbo='false'][data-turbo-frame='_top']", count: 2 do |links|
        links.each do |link|
          uri = URI.parse(link["href"])
          query = Rack::Utils.parse_query(uri.query)
          assert_equal location[:name], query["location_name"]
          assert_equal "Brighton", query["location"]
          assert_equal location[:country_code], query["country_code"]
          assert_equal location[:lat].to_s, query["lat"]
          if link.text == "Full Forecast"
            assert_equal forecast_full_path, uri.path
            assert_equal location[:lng].to_s, query["long"]
          else
            assert_equal "View Radar", link.text
            assert_equal radar_for_locale_web_path, uri.path
            assert_equal location[:lng].to_s, query["lng"]
            assert_equal "radar", query["type"]
          end
        end
      end
    end
  end

  def test_multiple_results_use_normalized_fields_and_include_country
    search("b", [@location, @location.merge(name: "Other", country_code: "nz")])
    assert_target("b")
    assert_select "form[action=?]", forecast_dual_full_path(locale: "en"), count: 2
    assert_select "input[name='country_code'][value='us']", count: 1
    assert_select "input[name='country_code'][value='nz']", count: 1
    assert_select "input[name='long'][value='-111.5845']", count: 2
    assert_select "input[name='turbo_location'][value='location_response_b']", count: 2
    assert_select "button", text: "Text Only Forecast", count: 0
  end

  def test_candidate_post_dispatches_us_and_non_us_and_accepts_symbol_periods
    %w[us nz].each do |country|
      calls = []
      select_location("a", country: country, forecast: ->(*args) { calls << args; country == "us" ? success(@period) : ServiceResult.new(success: true, value: [@period]) })
      assert_equal [[country == "us" ? "noaa" : "openweather", "40.5986", "-111.5845"]], calls
      assert_target("a")
      assert_select "#dual-a-period-title-0", "Tonight"
      assert_select ".forecast-full-detail", text: /0%/
    end
  end

  def test_non_us_single_result_uses_openweather
    calls = []
    search("b", [@location.merge(country_code: "nz")], forecast: ->(*args) { calls << args; ServiceResult.new(success: true, value: [@period]) })
    assert_equal [["openweather", 40.5986, -111.5845]], calls
    assert_select "#dual-b-period-title-0", "Tonight"
  end

  def test_both_sides_have_unique_dom_ids_and_valid_aria_references
    fragments = %w[a b].map do |side|
      select_location(side, forecast: ->(*) { success(@period, @period.merge(name: "Tomorrow")) })
      response.body
    end
    document = Nokogiri::HTML.fragment(fragments.join)
    ids = document.css("[id]").map { |element| element["id"] }
    assert_equal ids.uniq, ids
    document.css("[aria-controls], [aria-labelledby]").each do |element|
      reference = element["aria-controls"] || element["aria-labelledby"]
      assert_includes ids, reference
    end
    assert_equal 2, document.css("[data-controller='forecast-periods']").size
  end

  def test_forecast_failure_and_exception_do_not_replace_opposite_side
    select_location("a", forecast: ->(*) { success(@period) })
    assert_target("a")
    [ServiceResult.new(success: false, value: "Unavailable"), ->(*) { raise Timeout::Error }].each do |failure|
      select_location("b", forecast: failure)
      assert_target("b")
      assert_select "[role='alert']", text: /Unavailable|currently unavailable/
    end
    select_location("a", forecast: ServiceResult.new(success: false, value: "Unavailable"))
    assert_target("a")
  end

  def test_geocoder_exception_is_side_specific
    Google::GeoLocate.stub :call, ->(*) { raise Timeout::Error } do
      post forecast_dual_geo_location_path, params: { location: "Brighton", commit: "Locale A" }
    end
    assert_target("a")
    assert_select "[role='alert']", count: 1
  end

  def test_invalid_actions_targets_and_missing_country_make_no_service_call
    Google::GeoLocate.stub :call, ->(*) { flunk "Unexpected geocoder call" } do
      post forecast_dual_geo_location_path, params: { location: "Brighton", commit: "Invalid" }
      assert_response :unprocessable_entity
    end
    post forecast_dual_full_path, params: { turbo_location: "summary_response" }
    assert_response :unprocessable_entity
    select_location("a", country: nil)
    assert_target("a")
    assert_select "[role='alert']", text: /country are required/
  end

  private

  def post(*args, **kwargs)
    Weather::DiscussionForecaster.stub :call, ->(*) { flunk "Dual must not load discussion" } do
      Weather::AlertsForecaster.stub :call, ->(*) { flunk "Dual must not load alerts" } do
        super
      end
    end
  end

  def success(*periods)
    ServiceResult.new(success: true, value: { "forecasts" => periods })
  end

  def search(side, locations, forecast: ->(*) { flunk "Unexpected forecast call" }, geo_success: true)
    Google::GeoLocate.stub :call, ServiceResult.new(success: geo_success, value: locations) do
      Weather::Forecaster.stub :call, forecast do
        post forecast_dual_geo_location_path, params: { location: "Brighton", commit: "Locale #{side.upcase}" }
      end
    end
  end

  def select_location(side, country: "us", forecast: ->(*) { flunk "Unexpected forecast call" })
    Weather::Forecaster.stub :call, forecast do
      post forecast_dual_full_path, params: { lat: "40.5986", long: "-111.5845", location: "Brighton", location_name: "Brighton", country_code: country, turbo_location: "location_response_#{side}" }
    end
  end

  def assert_target(side)
    assert_response :success
    assert_select "turbo-stream[action='replace'][target='location_response_#{side}']", count: 1
    assert_select "turbo-stream", count: 1
    assert_select "turbo-frame#location_response_#{side}", count: 1
  end
end
