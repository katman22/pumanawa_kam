require_relative "../../../helpers/weather_monitoring_data"

class NoaaAlertsFetchTest < Minitest::Test
  include WeatherMonitoringData

  def setup
    Noaa::Request.any_instance.stubs(:sleep)
    HTTParty.stubs(:get).raises("Unexpected live NOAA request")
  end

  def test_empty_alerts_is_success
    HTTParty.expects(:get).returns(http_response(fixture("brighton_active_alerts")))
    result = Noaa::Alerts::Fetch.call(latitude: 40.5986, longitude: -111.5845)
    assert result.success?
    assert_empty result.value["features"]
  end

  def test_relevant_messages_are_preserved_and_pagination_is_followed
    body = fixture("ut_winter_alert_updates")
    body["pagination"] = { "next" => "https://api.weather.gov/alerts?cursor=next" }
    HTTParty.expects(:get).twice.returns(http_response(body), http_response("features" => []))
    result = Noaa::Alerts::Fetch.call(latitude: 40, longitude: -111)
    assert result.success?
    assert_equal body["features"], result.value["features"]
    assert result.value["features"].any? { |f| f["properties"]["event"] == "Winter Weather Advisory" }
  end

  def test_pagination_failure_is_not_partial_success
    HTTParty.expects(:get).twice.returns(http_response("features" => [], "pagination" => { "next" => "https://api.weather.gov/alerts?cursor=next" }), http_response({}, code: 429))
    assert Noaa::Alerts::Fetch.call(latitude: 40, longitude: -111).failure?
  end

  def test_missing_features_and_pagination_cycle_fail
    HTTParty.expects(:get).returns(http_response({}))
    assert Noaa::Alerts::Fetch.call(latitude: 40, longitude: -111).failure?
    body = { "features" => [], "pagination" => { "next" => "https://api.weather.gov/alerts?active=true&point=40.0,-111.0" } }
    HTTParty.expects(:get).once.returns(http_response(body))
    assert Noaa::Alerts::Fetch.call(latitude: 40, longitude: -111).failure?
  end
end
