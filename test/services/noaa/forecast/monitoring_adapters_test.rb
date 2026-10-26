require_relative "../../../helpers/weather_monitoring_data"

class NoaaMonitoringAdaptersTest < Minitest::Test
  include WeatherMonitoringData

  def setup
    Noaa::Request.any_instance.stubs(:sleep)
    HTTParty.stubs(:get).raises("Unexpected live NOAA request")
  end

  def test_point_mapping_and_invalid_structure
    HTTParty.expects(:get).with("https://api.weather.gov/points/40.5986,-111.5845", anything).returns(http_response(fixture("brighton_points")))
    result = Noaa::Forecast::Point.call(latitude: 40.5986, longitude: -111.5845)
    assert result.success?
    assert_equal "SLC", result.value["gridId"]
    assert_equal 110, result.value["gridX"]
    assert_equal 167, result.value["gridY"]
    HTTParty.expects(:get).returns(http_response("properties" => {}))
    assert Noaa::Forecast::Point.call(latitude: 40, longitude: -111).failure?
  end

  def test_timeout_is_bounded_to_two_attempts
    HTTParty.expects(:get).twice.raises(Net::ReadTimeout)
    result = Noaa::Forecast::Point.call(latitude: 40, longitude: -111)
    assert result.failure?
    assert_equal "transport_error", result.value[:code]
  end

  def test_rate_limit_honors_retry_after_without_retry
    HTTParty.expects(:get).once.returns(http_response({}, code: 429, headers: { "Retry-After" => "7200" }))
    result = Noaa::Forecast::Point.call(latitude: 40, longitude: -111)
    assert_equal "rate_limited", result.value[:code]
    assert_operator result.value[:retry_at], :>, Time.current + 119.minutes
  end

  def test_server_failure_has_one_retry
    HTTParty.expects(:get).twice.returns(http_response({}, code: 503))
    assert_equal "http_503", Noaa::Forecast::Point.call(latitude: 40, longitude: -111).value[:code]
  end

  def test_grid_200_and_conditional_304
    mapping = fixture("brighton_points")["properties"]
    HTTParty.expects(:get).returns(http_response(fixture("brighton_grid"), headers: { "Last-Modified" => "Tue, 20 Oct 2026 06:31:29 GMT" }))
    result = Noaa::Forecast::GridData.call(mapping: mapping)
    assert result.success?
    assert_equal "2026-10-20T06:31:29+00:00", result.value.dig("body", "properties", "updateTime")
    HTTParty.expects(:get).with(mapping["forecastGridData"], has_entry(:headers, has_entry("If-Modified-Since", "marker"))).returns(http_response("", code: 304))
    cached = Noaa::Forecast::GridData.call(mapping: mapping, validators: { "If-Modified-Since" => "marker" }, retained: result.value["body"])
    assert cached.success?
    assert_equal result.value["body"], cached.value["body"]
  end

  def test_304_without_retained_body_recovers_unconditionally_once
    HTTParty.expects(:get).twice.returns(http_response("", code: 304), http_response(fixture("brighton_grid")))
    assert Noaa::Forecast::GridData.call(mapping: fixture("brighton_points")["properties"]).success?
  end

  def test_repeated_304_and_malformed_json_are_failures
    HTTParty.expects(:get).twice.returns(http_response("", code: 304))
    assert Noaa::Forecast::GridData.call(mapping: fixture("brighton_points")["properties"]).failure?
    HTTParty.expects(:get).returns(http_response("not-json"))
    assert_equal "malformed_json", Noaa::Forecast::Point.call(latitude: 40, longitude: -111).value[:code]
  end

  def test_problem_payload_is_not_empty_success_and_foreign_urls_are_rejected
    HTTParty.expects(:get).returns(http_response("status" => 500, "title" => "failure"))
    assert Noaa::Forecast::Point.call(latitude: 40, longitude: -111).failure?
    assert Noaa::Request.call(url: "https://example.com/grid").failure?
  end
  def test_grid_wrong_identity_and_bad_timestamp_fail
    raw = fixture("brighton_grid")
    raw["properties"]["gridX"] = 999
    HTTParty.expects(:get).returns(http_response(raw))
    assert Noaa::Forecast::GridData.call(mapping: fixture("brighton_points")["properties"]).failure?
    raw["properties"]["gridX"] = 110
    raw["properties"]["updateTime"] = "bad"
    HTTParty.expects(:get).returns(http_response(raw))
    assert Noaa::Forecast::GridData.call(mapping: fixture("brighton_points")["properties"]).failure?
  end
  def test_response_validator_headers_accept_strings_and_one_element_arrays
    mapping = fixture("brighton_points")["properties"]
    stamp = "Tue, 20 Oct 2026 06:31:29 GMT"
    [ stamp, [ stamp ] ].each do |value|
      HTTParty.expects(:get).returns(http_response(fixture("brighton_grid"), headers: { "Last-Modified" => value, "ETag" => value.is_a?(Array) ? [ 'W/"grid"' ] : 'W/"grid"' }))
      result = Noaa::Forecast::GridData.call(mapping: mapping)
      assert result.success?, result.value.inspect
      assert_equal stamp, result.value["headers"]["last-modified"]
      assert_equal 'W/"grid"', result.value["headers"]["etag"]
      assert_kind_of String, result.value["headers"]["last-modified"]
    end
  end

  def test_legacy_persisted_validator_arrays_reach_httparty_as_strings
    stamp = "Tue, 20 Oct 2026 06:31:29 GMT"
    HTTParty.expects(:get).with do |_url, options|
      headers = options.fetch(:headers)
      assert_equal stamp, headers["If-Modified-Since"]
      assert_equal 'W/"grid"', headers["If-None-Match"]
      refute_kind_of Array, headers["If-Modified-Since"]
      true
    end.returns(http_response("", code: 304, headers: { "Last-Modified" => [ stamp ], "ETag" => [ 'W/"grid"' ] }))
    result = Noaa::Forecast::GridData.call(mapping: fixture("brighton_points")["properties"],
      validators: { "If-Modified-Since" => [ stamp ], "If-None-Match" => [ 'W/"grid"' ] }, retained: fixture("brighton_grid"))
    assert result.success?
    assert_equal 304, result.value["status"]
  end
end
