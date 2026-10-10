# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "../../config/environment"
require "minitest/autorun"
require "minitest/mock"

class FindForecastControllerTest < ActionDispatch::IntegrationTest
  def test_find_page_has_shared_header_navigation_and_original_search_form
    get forecast_path
    assert_response :success
    assert_select ".forecast-find .forecast-full-header h1", "Find a Forecast"
    assert_select ".forecast-full-brand img", count: 1
    assert_select ".forecast-full-header a[href=?]", forecast_dual_path(locale: "en"), text: "Dual Screen Forecasts"
    assert_select "figcaption", count: 1
    assert_select "nav[aria-label='Forecast navigation']", count: 1
    assert_select "nav a[href=?][data-turbo-frame='_top']", forecast_path(locale: "en"), text: "Find Another Forecast"
    assert_select "nav a[href=?]", aura_weather_forecasts_root_path(locale: "en"), text: "Kainga"
    assert_select "form#location_form[action=?][method='post'][data-turbo-frame='location_response']", forecast_geo_location_path(locale: "en")
    assert_select "label[for='location']", "Location"
    assert_select "input#location[name='location']", count: 1
    assert_select "input[type='submit'][name='commit'][value='Go']", count: 1
    assert_select "turbo-frame#location_response", count: 1
    assert_select "turbo-frame#summary_response", count: 1
    refute_includes response.body, "Back to Summary"
    refute_includes response.body, "history.back"
  end

  def test_search_still_returns_original_turbo_stream_targets
    Google::GeoLocate.stub :call, ServiceResult.new(success: true, value: []) do
      post forecast_geo_location_path, params: { location: "Brighton" }, as: :turbo_stream
    end
    assert_response :success
    assert_select "turbo-stream[action='replace'][target='location_response']", count: 1
    assert_select "turbo-stream[action='replace'][target='summary_response']", count: 1
  end

  def test_dual_and_text_only_share_navigation_without_duplicate_attribution
    get forecast_dual_path
    assert_shared_navigation
    Weather::Forecaster.stub :call, ServiceResult.new(success: true, value: { "forecasts" => [] }) do
      get forecast_text_only_path, params: { lat: "40.5986", long: "-111.5845", country_code: "us", location_name: "Brighton" }
    end
    assert_shared_navigation
  end

  def test_text_only_uses_centered_header_and_preserves_all_period_text
    Weather::Forecaster.stub :call, ServiceResult.new(success: true, value: { "forecasts" => [
      { "name" => "Tonight", "detailedForecast" => "Clear overnight." },
      { "name" => "Tomorrow", "detailedForecast" => "Rain <b>later</b>." }
    ] }) do
      get forecast_text_only_path, params: { lat: "40.5986", long: "-111.5845", country_code: "us", location_name: "Brighton" }
    end
    assert_shared_navigation
    assert_select ".forecast-full.forecast-text-only", count: 1
    assert_select ".forecast-full-header h1", "Brighton"
    assert_select ".forecast-full-eyebrow", "Text Only Forecast"
    assert_select ".forecast-full-brand img", count: 1
    assert_select ".forecast-full-detail", count: 2
    assert_select ".forecast-full-detail h2", text: "Tonight"
    assert_select ".forecast-full-detail p", text: "Clear overnight."
    assert_select ".forecast-full-detail p", text: "Rain <b>later</b>."
    assert_select ".forecast-full-detail b", count: 0
    assert_select ".forecast-full-header-utilities .d-flex a:first-child", text: "Full Forecast" do |links|
      uri = URI.parse(links.first["href"])
      assert_equal forecast_full_path, uri.path
      query = Rack::Utils.parse_query(uri.query)
      assert_equal "Brighton", query["location_name"]
      assert_equal "40.5986", query["lat"]
      assert_equal "-111.5845", query["long"]
      assert_equal "us", query["country_code"]
    end
    assert_select ".forecast-full-header-utilities .d-flex a:last-child", text: "View Radar"
    assert_select ".forecast-full-header a", text: "View Radar" do |links|
      query = Rack::Utils.parse_query(URI.parse(links.first["href"]).query)
      assert_equal "Brighton", query["location_name"]
      assert_equal "40.5986", query["lat"]
      assert_equal "-111.5845", query["lng"]
      assert_equal "us", query["country_code"]
    end
  end

  def test_text_only_displays_service_failure
    Weather::Forecaster.stub :call, ServiceResult.new(success: false, value: "Forecast unavailable") do
      get forecast_text_only_path, params: { lat: "40.5986", long: "-111.5845", country_code: "us" }
    end
    assert_response :success
    assert_select "[role='alert']", "Error Response: Forecast unavailable"
    assert_select ".forecast-full-detail", count: 0
  end

  private

  def assert_shared_navigation
    assert_response :success
    assert_select "figcaption", count: 1
    assert_select "nav a[href=?]", forecast_path(locale: "en"), text: "Find Another Forecast"
    refute_includes response.body, "Back to Summary"
    refute_includes response.body, "history.back"
  end
end
