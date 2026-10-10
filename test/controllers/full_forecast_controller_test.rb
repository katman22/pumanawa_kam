# frozen_string_literal: true

# This action uses services and session data, not database fixtures.
ENV["RAILS_ENV"] = "test"
require_relative "../../config/environment"
require "minitest/autorun"
require "minitest/mock"

class FullForecastControllerTest < ActionDispatch::IntegrationTest
  def setup
    @period = {
      name: "Tonight", icon: nil, isDaytime: false, temperature: 36,
      temperatureUnit: "F", shortForecast: "Mostly clear", detailedForecast: "Clear overnight.",
      windDirection: "W", windSpeed: "7 mph", probabilityOfPrecipitation: { value: nil }
    }
    @params = { lat: "40.5986", long: "-111.5845", country_code: "us", location_name: "Brighton" }
  end

  def test_full_page_renders_all_periods_and_discussion_with_correct_radar_coordinates
    forecasts = Minitest::Mock.new
    forecasts.expect :call, ServiceResult.new(success: true, value: { "forecasts" => [ @period, @period.merge(name: "Tomorrow") ] }), [ "noaa", "40.5986", "-111.5845" ]
    discussion = Minitest::Mock.new
    discussion.expect :call, ServiceResult.new(success: true, value: { short_term: "Key message.\nSecond line.", long_range: "Detailed discussion." }), [ "noaa", "40.5986", "-111.5845" ]
    Weather::Forecaster.stub :call, forecasts do
      Weather::DiscussionForecaster.stub :call, discussion do
        get forecast_full_path, params: @params
      end
    end
    forecasts.verify
    discussion.verify
    assert_response :success
    assert_select ".forecast-full-header h1", "Brighton"
    assert_select "nav a[href=?]", forecast_path(locale: "en"), text: "Find Another Forecast"
    assert_select "figcaption", count: 1
    refute_includes response.body, "Back to Summary"
    assert_select ".forecast-full-header a[data-turbo='false']" do |links|
      query = Rack::Utils.parse_query(URI.parse(links.first["href"]).query)
      assert_equal "40.5986", query["lat"]
      assert_equal "-111.5845", query["lng"]
      assert_equal "radar", query["type"]
      assert_equal "Brighton", query["location_name"]
      assert_equal "us", query["country_code"]
    end
    assert_select "button[data-forecast-periods-target='card'][type='button']", count: 2
    assert_select "section[data-forecast-periods-target='detail']", count: 2
    assert_select ".forecast-full-summary p", "Key message. Second line."
    assert_select ".forecast-full-long-range p", "Detailed discussion."
    assert_select ".forecast-full-discussion a", count: 0
    assert_select "[data-forecast-tabs-target='panel']", count: 3
    assert_select "#forecast-tab-periods[aria-selected='true']", "Forecast Periods"
    assert_select ".forecast-full-header .forecast-full-brand img", count: 1
    refute_includes response.body, "Weather Tips"
    refute_includes response.body, "Current Location"
  end

  def test_discussion_failure_does_not_hide_forecasts
    get_full_with_discussion(ServiceResult.new(success: false, value: "Unavailable"))
    assert_response :success
    assert_select ".forecast-full-detail", text: /Clear overnight/
    assert_select ".forecast-full-summary p", "No forecast available"
    assert_select ".forecast-full-long-range p", "No extended forecast available"
  end

  def test_discussion_exception_does_not_hide_forecasts
    get_full_with_discussion(->(*) { raise Timeout::Error, "Provider timeout" })
    assert_response :success
    assert_select ".forecast-full-detail", text: /Clear overnight/
    assert_select ".forecast-full-summary p", "No forecast available"
  end

  def test_provider_text_is_escaped
    get_full_with_discussion(ServiceResult.new(success: true, value: { short_term: "<script>alert(1)</script>", long_range: "<b>Text</b>" }))
    assert_select ".forecast-full-discussion script", count: 0
    assert_select ".forecast-full-discussion b", count: 0
    assert_select ".forecast-full-summary p", "<script>alert(1)</script>"
  end

  def test_discussion_reflows_wrapped_lines_and_preserves_paragraphs
    get_full_with_discussion(ServiceResult.new(success: true, value: {
      short_term: "First wrapped\nsummary line.\n\nSecond paragraph.",
      long_range: "First wrapped\r\n  discussion line.\r\n \r\nSecond wrapped\r\nparagraph."
    }))
    assert_select ".forecast-full-summary p", "First wrapped summary line.\n\nSecond paragraph."
    assert_select ".forecast-full-long-range p", "First wrapped discussion line.\n\nSecond wrapped paragraph."
  end

  def test_radar_reuses_header_and_links_back_to_same_location_without_weather_calls
    forecasts = Minitest::Mock.new
    discussion = Minitest::Mock.new
    @alert_result = Minitest::Mock.new
    Weather::Forecaster.stub :call, forecasts do
      Weather::DiscussionForecaster.stub :call, discussion do
        get radar_for_locale_web_path, params: @params.except(:long).merge(lng: @params[:long], location: "Brighton Utah", type: "radar")
      end
    end
    forecasts.verify
    discussion.verify
    @alert_result.verify
    assert_response :success
    assert_select ".forecast-full-header h1", "Brighton"
    assert_select ".forecast-full-eyebrow", "Weather Radar"
    assert_select "nav a[href=?]", forecast_path(locale: "en"), text: "Find Another Forecast"
    assert_select "figcaption", count: 1
    refute_includes response.body, "history.back"
    assert_select ".forecast-full-brand img", count: 1
    assert_select ".forecast-full-header a[data-turbo='false']", text: "Full forecast" do |links|
      uri = URI.parse(links.first["href"])
      assert_equal forecast_full_path, uri.path
      query = Rack::Utils.parse_query(uri.query)
      assert_equal "40.5986", query["lat"]
      assert_equal "-111.5845", query["long"]
      assert_equal "us", query["country_code"]
      assert_equal "Brighton", query["location_name"]
      assert_equal "Brighton Utah", query["location"]
    end
    assert_select "[data-controller='weather-map'][data-weather-map-lng='-111.5845'][data-weather-map-type='radar']", count: 1
  end

  def test_radar_recovers_missing_name_from_same_location_in_session
    get_full_with_discussion(ServiceResult.new(success: true, value: {}))
    get radar_for_locale_web_path, params: { lat: @params[:lat], lng: @params[:long] }
    assert_select ".forecast-full-header h1", "Brighton"
    assert_select ".forecast-full-header a", text: "Full forecast" do |links|
      query = Rack::Utils.parse_query(URI.parse(links.first["href"]).query)
      assert_equal "Brighton", query["location_name"]
      assert_equal "us", query["country_code"]
    end
    get radar_for_locale_web_path, params: { lat: @params[:lat], lng: @params[:long], location_name: "Explicit name" }
    assert_select ".forecast-full-header h1", "Explicit name"
    get radar_for_locale_web_path, params: { lat: "41", lng: "-112" }
    assert_select ".forecast-full-header h1", "Current location"
  end

  def test_forecast_failure_preserves_error_and_skips_discussion
    @alert_result = Minitest::Mock.new
    discussion = Minitest::Mock.new
    Weather::Forecaster.stub :call, ServiceResult.new(success: false, value: "Forecast unavailable") do
      Weather::DiscussionForecaster.stub :call, discussion do
        get forecast_full_path, params: @params
      end
    end
    discussion.verify
    assert_response :success
    @alert_result.verify
    assert_select "[role='alert']", "Error Response: Forecast unavailable"
    assert_select ".forecast-full-card", count: 0
  end

  def test_non_us_forecast_keeps_openweather_dispatch
    @alert_result = Minitest::Mock.new
    @alert_result.expect :call, ServiceResult.new(success: true, value: { "alerts" => [] }), [ "openweather", "40.5986", "-111.5845" ]
    forecasts = Minitest::Mock.new
    forecasts.expect :call, ServiceResult.new(success: true, value: [ @period ]), [ "openweather", "40.5986", "-111.5845" ]
    discussion = Minitest::Mock.new
    discussion.expect :call, ServiceResult.new(success: true, value: { short_term: "Summary", long_range: "Details" }), [ "openweather", "40.5986", "-111.5845" ]
    Weather::Forecaster.stub :call, forecasts do
      Weather::DiscussionForecaster.stub :call, discussion do
        get forecast_full_path, params: @params.merge(country_code: "nz")
      end
    end
    forecasts.verify
    discussion.verify
    assert_response :success
    @alert_result.verify
    assert_select ".forecast-full-card", count: 1
  end

  def test_alerts_render_count_and_escaped_details
    alerts = Minitest::Mock.new
    alerts.expect :call, ServiceResult.new(success: true, value: { "alerts" => [{ headline: "Winter warning", description: "<script>unsafe</script>", instruction: "Stay indoors.", severity: "Severe" }] }), [ "noaa", "40.5986", "-111.5845" ]
    get_full_with_discussion(ServiceResult.new(success: true, value: {}), alerts: alerts)
    alerts.verify
    assert_select "#forecast-tab-alerts", "Alerts (1)"
    assert_select ".forecast-full-alert h3", "Winter warning"
    assert_select ".forecast-full-alert script", count: 0
    assert_select ".forecast-full-alert", text: /Stay indoors/
  end

  def test_empty_alerts
    get_full_with_discussion(ServiceResult.new(success: true, value: {}))
    assert_select ".forecast-full-alerts p", "No active weather alerts."
    assert_select "#forecast-tab-alerts", "Alerts"
  end

  def test_alert_text_reflows_wrapped_lines_and_preserves_paragraphs
    alerts = ServiceResult.new(success: true, value: { "alerts" => [{
      headline: "Winter warning",
      description: "Snow is\nexpected.\n\nTravel may be\ndifficult.",
      instruction: "Stay\r\nindoors.\r\n \r\nAvoid <b>travel</b>."
    }] })
    get_full_with_discussion(ServiceResult.new(success: true, value: {}), alerts: alerts)
    assert_select ".forecast-full-alert p", text: "Snow is expected.\n\nTravel may be difficult."
    assert_select ".forecast-full-alert p", text: "Stay indoors.\n\nAvoid <b>travel</b>."
    assert_select ".forecast-full-alert b", count: 0
  end

  def test_alert_failure_and_exception_preserve_other_panels
    [ServiceResult.new(success: false, value: "Unavailable"), ->(*) { raise Timeout::Error }].each do |alerts|
      get_full_with_discussion(ServiceResult.new(success: true, value: { short_term: "Summary intact" }), alerts: alerts)
      assert_select ".forecast-full-alerts p", "Weather alerts are currently unavailable."
      assert_select ".forecast-full-summary p", "Summary intact"
      assert_select ".forecast-full-detail", text: /Clear overnight/
    end
  end

  private

  def get(*args, **kwargs)
    Weather::AlertsForecaster.stub :call, (@alert_result || ServiceResult.new(success: true, value: { "alerts" => [] })) do
      super
    end
  end

  def get_full_with_discussion(result, alerts: nil)
    @alert_result = alerts
    Weather::Forecaster.stub :call, ServiceResult.new(success: true, value: { "forecasts" => [ @period ] }) do
      Weather::DiscussionForecaster.stub :call, result do
        get forecast_full_path, params: @params
      end
    end
  end
end
