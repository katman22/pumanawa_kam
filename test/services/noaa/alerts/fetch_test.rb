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

  def test_bounded_history_query_is_opt_in_and_preserves_explicit_cancellation
    body = fixture("brighton_alert_signal")
    body["features"][0]["properties"]["messageType"] = "Cancel"
    HTTParty.expects(:get).with do |url, _options|
      query = URI.decode_www_form(URI(url).query).to_h
      assert_equal "40.5986,-111.5845", query["point"]
      assert_equal ANCHOR.iso8601, query["start"]
      refute query.key?("active")
      true
    end.returns(http_response(body))
    result = Noaa::Alerts::Fetch.call(latitude: 40.5986, longitude: -111.5845, active: false, since: ANCHOR)
    assert result.success?
    assert_equal "Cancel", result.value["features"][0]["properties"]["messageType"]
    HTTParty.expects(:get).never
    assert_equal "invalid_alert_window", Noaa::Alerts::Fetch.call(latitude: 40, longitude: -111, active: false).value[:code]
  end

  def test_explicit_history_end_is_sent_and_invalid_windows_fail_before_http
    HTTParty.expects(:get).with do |url, _options|
      query = URI.decode_www_form(URI(url).query).to_h
      assert_equal ANCHOR.iso8601, query["end"]
      assert_equal (ANCHOR - 24.hours).iso8601, query["start"]
      true
    end.returns(http_response("features" => []))
    result = Noaa::Alerts::Fetch.call(latitude: 40, longitude: -111, active: false, since: ANCHOR - 24.hours, through: ANCHOR)
    assert result.success?
    HTTParty.expects(:get).never
    assert Noaa::Alerts::Fetch.call(latitude: 40, longitude: -111, active: false, since: ANCHOR, through: ANCHOR).failure?
    assert Noaa::Alerts::Fetch.call(latitude: 40, longitude: -111, through: ANCHOR).failure?
  end

  def test_bounded_pagination_requires_the_same_geographic_and_time_window
    params = URI.encode_www_form(point: "40.0,-111.0", start: (ANCHOR - 24.hours).iso8601, end: ANCHOR.iso8601, cursor: "next")
    next_page = "https://api.weather.gov/alerts?#{params}"
    HTTParty.expects(:get).twice.returns(http_response("features" => [], "pagination" => { "next" => next_page }), http_response("features" => []))
    assert Noaa::Alerts::Fetch.call(latitude: 40, longitude: -111, active: false, since: ANCHOR - 24.hours, through: ANCHOR).success?
    HTTParty.expects(:get).once.returns(http_response("features" => [], "pagination" => { "next" => "https://api.weather.gov/alerts?cursor=ambiguous" }))
    result = Noaa::Alerts::Fetch.call(latitude: 40, longitude: -111, active: false, since: ANCHOR - 24.hours, through: ANCHOR)
    assert result.failure?
    assert_equal "alert_pagination_scope_changed", result.value[:code]
  end

  def bounded_fetch
    Noaa::Alerts::Fetch.call(latitude: 40, longitude: -111, active: false, since: ANCHOR - 24.hours, through: ANCHOR)
  end

  def test_present_pagination_requires_next_and_never_returns_partial_features
    [ {}, { "previous" => "https://api.weather.gov/alerts?cursor=previous" } ].each do |pagination|
      body = fixture("brighton_alert_signal").merge("pagination" => pagination)
      HTTParty.expects(:get).once.returns(http_response(body))
      result = bounded_fetch
      assert result.failure?
      assert_equal "alert_pagination_invalid", result.value[:code]
      refute result.value.key?("features")
    end
  end

  def test_malformed_pagination_on_a_later_page_discards_the_entire_collection
    first = fixture("brighton_alert_signal").merge("pagination" => { "next" => continuation })
    HTTParty.expects(:get).twice.returns(http_response(first), http_response("features" => [], "pagination" => {}))
    result = bounded_fetch
    assert result.failure?
    assert_equal "alert_pagination_invalid", result.value[:code]
    refute result.value.key?("features")
  end

  def test_absent_pagination_and_null_next_remain_terminal_for_history_and_active_queries
    [ {}, { "pagination" => { "next" => nil } } ].each do |metadata|
      [ true, false ].each do |active|
        HTTParty.expects(:get).once.returns(http_response({ "features" => [] }.merge(metadata)))
        result = active ? Noaa::Alerts::Fetch.call(latitude: 40, longitude: -111) : bounded_fetch
        assert result.success?, result.value.inspect
        assert_empty result.value["features"]
      end
    end
  end

  def continuation(**overrides)
    "https://api.weather.gov/alerts?#{URI.encode_www_form({ point: '40.0,-111.0', start: (ANCHOR - 24.hours).iso8601,
      end: ANCHOR.iso8601, cursor: 'next' }.merge(overrides))}"
  end

  def test_bounded_pagination_rejects_additional_narrowing_filters
    %i[message_type status event zone area active unknown].each do |filter|
      HTTParty.expects(:get).at_least_once.returns(http_response("features" => [], "pagination" => { "next" => continuation(**{ filter => "alert" }) }), http_response("features" => []))
      result = bounded_fetch
      assert result.failure?, "new #{filter} filter must not silently narrow the source collection"
      assert_equal "alert_pagination_scope_changed", result.value[:code]
    end
  end

  def test_bounded_pagination_rejects_duplicate_query_parameters
    %w[point start end cursor limit].each do |key|
      value = { "point" => "40.0,-111.0", "start" => (ANCHOR - 24.hours).iso8601,
        "end" => ANCHOR.iso8601, "cursor" => "next", "limit" => "100" }.fetch(key)
      link = continuation(limit: 100) + "&#{URI.encode_www_form(key => value)}"
      HTTParty.expects(:get).at_least_once.returns(http_response("features" => [], "pagination" => { "next" => link }), http_response("features" => []))
      assert bounded_fetch.failure?, "duplicate #{key} must be rejected even when values agree"
    end
  end

  def test_pagination_rejects_malformed_termination_values
    [ false, 0, [], {}, "" ].each do |value|
      HTTParty.expects(:get).once.returns(http_response("features" => [], "pagination" => { "next" => value }))
      result = bounded_fetch
      assert result.failure?, "pagination.next=#{value.inspect} is not valid termination"
    end
  end

  def test_bounded_pagination_allows_cursor_and_page_size_but_preserves_semantics
    HTTParty.expects(:get).twice.returns(http_response("features" => [], "pagination" => { "next" => continuation(limit: 100) }),
      http_response("features" => [], "pagination" => { "next" => nil }))
    assert bounded_fetch.success?
  end

  def test_bounded_pagination_rejects_changed_removed_and_invalid_pagination_parameters
    pairs = URI.decode_www_form(URI(continuation).query)
    removed = %w[point start end].map do |key|
      "https://api.weather.gov/alerts?#{URI.encode_www_form(pairs.reject { |name, _value| name == key })}"
    end
    changed = [ continuation(point: "41,-111"), continuation(start: (ANCHOR - 1.hour).iso8601),
      continuation(end: (ANCHOR + 1.hour).iso8601), continuation(limit: 0), continuation(limit: -1), continuation(limit: "many"), continuation(cursor: "") ]
    (removed + changed).each do |link|
      HTTParty.expects(:get).once.returns(http_response("features" => [], "pagination" => { "next" => link }))
      assert bounded_fetch.failure?
    end
  end

  def test_bounded_pagination_accepts_equivalent_timestamp_and_coordinate_formatting
    next_page = continuation(point: "40,-111", start: (ANCHOR - 24.hours).getlocal("-06:00").iso8601,
      end: ANCHOR.getlocal("-06:00").iso8601, limit: 50)
    HTTParty.expects(:get).twice.returns(http_response("features" => [], "pagination" => { "next" => next_page }), http_response("features" => []))
    assert bounded_fetch.success?
  end
end
