require "test_helper"
require_relative "../../helpers/weather_monitoring_data"

class WeatherMonitoringRunEvaluationTest < ActiveSupport::TestCase
  include WeatherMonitoringData

  # A real second PostgreSQL session must see committed test data, and the guard
  # deliberately refuses open transactions. Cleanup is limited to our own rows.
  self.use_transactional_tests = false

  setup do
    @resort = pilot_resort
    @resort_ids = [ @resort.id ]
    HTTParty.stubs(:get).raises("Unexpected live NOAA request")
  end

  teardown do
    ResortWeatherMonitor.where(resort_id: @resort_ids).delete_all
    WeatherForecastObservation.where(resort_id: @resort_ids).delete_all
    Resort.where(id: @resort_ids).delete_all
  end

  def run_evaluation(**options)
    WeatherMonitoring::RunEvaluation.call(resort: @resort, persist: true, evaluation_at: ANCHOR, **options)
  end

  def success
    ServiceResult.new(success: true, value: { observation: "existing" })
  end

  test "delegates object and ID preserving modes and ServiceResult outside transactions" do
    [ @resort, @resort.id ].each do |input|
      expected = success
      WeatherMonitoring::EvaluateResort.expects(:call).with do |**options|
        assert_equal @resort, options[:resort]
        assert_equal true, options[:persist]
        assert_equal true, options[:probe]
        assert_equal false, options[:fetch_alerts]
        assert_equal ANCHOR, options[:evaluation_at]
        refute ResortWeatherMonitor.connection_pool.with_connection(&:transaction_open?)
        true
      end.returns(expected)
      result = WeatherMonitoring::RunEvaluation.call(resort: input, persist: true, probe: true, fetch_alerts: false, evaluation_at: ANCHOR)
      assert_same expected, result
    end
  end

  test "concurrent manual callers acquire only once across database sessions" do
    entered, release, result = Queue.new, Queue.new, Queue.new
    worker = nil
    ResortWeatherMonitor.cache do
      calls = Queue.new
      evaluation = lambda do |**_options|
        calls << true
        entered << true
        release.pop
        success
      end
      WeatherMonitoring::EvaluateResort.stub(:call, evaluation) do
        worker = Thread.new do
          result << run_evaluation
        rescue StandardError => error
          result << error
        end
        Timeout.timeout(10) { entered.pop }
        busy = run_evaluation(probe: true)
        assert busy.failure?
        assert_equal "evaluation_busy", busy.value[:code]
        release << true
        completed = Timeout.timeout(10) { result.pop }
        raise completed if completed.is_a?(Exception)

        assert completed.success?
        worker.join
        assert_equal 1, calls.size
      end
      WeatherMonitoring::EvaluateResort.expects(:call).returns(success)
      assert run_evaluation.success?, "lock must be released before returning the connection"
    end
  ensure
    release << true if release
    worker&.join(10)
  end

  test "failure results release the session lock and propagate unchanged" do
    failure = ServiceResult.new(success: false, value: { code: "transport_error" })
    WeatherMonitoring::EvaluateResort.expects(:call).returns(failure)
    assert_same failure, run_evaluation
    assert_unlocked_from_another_session
  end

  test "repeated successful runs release real locks even with query caching enabled" do
    WeatherMonitoring::EvaluateResort.expects(:call).times(3).returns(success)
    ResortWeatherMonitor.cache do
      3.times do
        assert run_evaluation.success?
        assert_unlocked_from_another_session
      end
    end
  end

  test "programming exceptions release the lock and are not hidden" do
    WeatherMonitoring::EvaluateResort.expects(:call).raises(ArgumentError, "test bug")
    assert_raises(ArgumentError) { run_evaluation }
    assert_unlocked_from_another_session
  end

  test "database errors return ServiceResult and release the lock" do
    WeatherMonitoring::EvaluateResort.expects(:call).raises(ActiveRecord::StatementInvalid, "test DB failure")
    result = run_evaluation
    assert result.failure?
    assert_equal "persistence_error", result.value[:code]
    assert_unlocked_from_another_session
  end

  test "enclosing transaction fails closed without evaluating or acquiring session lock" do
    WeatherMonitoring::EvaluateResort.expects(:call).never
    ResortWeatherMonitor.transaction do
      result = run_evaluation
      assert result.failure?
      assert_equal "evaluation_transaction_open", result.value[:code]
    end
    assert_unlocked_from_another_session
  end

  test "failed unlock disconnects the owning session rather than leaking its lock into the pool" do
    WeatherMonitoring::EvaluateResort.expects(:call).returns(success)
    ResortWeatherMonitor.connection_pool.with_connection do |connection|
      select = connection.method(:select_value)
      disconnect = connection.method(:disconnect!)
      disconnected = false
      query = lambda do |sql, *args, **kwargs|
        raise ActiveRecord::StatementInvalid, "simulated unlock failure" if sql.include?("pg_advisory_unlock")

        select.call(sql, *args, **kwargs)
      end
      close_session = lambda do
        disconnected = true
        disconnect.call
      end
      connection.stub(:select_value, query) do
        connection.stub(:disconnect!, close_session) do
          result = run_evaluation
          assert result.failure?
          assert_equal "persistence_error", result.value[:code]
        end
      end
      assert disconnected
    end
    assert_unlocked_from_another_session
  end

  test "missing and unsupported resorts are rejected without evaluation" do
    WeatherMonitoring::EvaluateResort.expects(:call).never
    [ nil, -1, Resort.new(slug: "brighton") ].each do |input|
      result = WeatherMonitoring::RunEvaluation.call(resort: input)
      assert_equal "resort_missing", result.value[:code]
    end
    other = Resort.create!(resort_name: "Guard test only", slug: "guard-test-only", latitude: 40, longitude: -111)
    @resort_ids << other.id
    result = WeatherMonitoring::RunEvaluation.call(resort: other)
    assert_equal "pilot_resorts_only", result.value[:code]
  end

  test "guarded fixture pipeline preserves disabled and rate limit protections" do
    mapping = fixture("brighton_points")["properties"].merge("latitude" => @resort.latitude, "longitude" => @resort.longitude)
    monitor = ResortWeatherMonitor.create!(resort: @resort)
    Noaa::Forecast::Point.expects(:call).never
    assert_equal "monitor_disabled", run_evaluation.value[:code]
    monitor.update!(enabled: true, last_error_code: "rate_limited", next_probe_at: ANCHOR + 2.hours)
    assert_equal "rate_limited", run_evaluation.value[:code]
    monitor.update!(last_error_code: nil)
    Noaa::Forecast::Point.unstub(:call)
    Noaa::Forecast::Point.expects(:call).returns(ServiceResult.new(success: true, value: mapping))
    Noaa::Forecast::GridData.expects(:call).returns(ServiceResult.new(success: true,
      value: { "status" => 200, "body" => fixture("brighton_grid"), "headers" => {} }))
    assert_difference "WeatherForecastObservation.count", 1 do
      result = run_evaluation(fetch_alerts: false)
      assert result.success?, result.value.inspect
    end
    assert_equal ANCHOR, monitor.reload.last_success_at
  end

  test "scheduled due recheck bypasses cached state changed at lock acquisition" do
    travel_to ANCHOR
    monitor = ResortWeatherMonitor.create!(resort: @resort, enabled: true, next_check_at: ANCHOR, next_probe_at: ANCHOR)
    WeatherMonitoring::EvaluateResort.expects(:call).never
    ResortWeatherMonitor.connection_pool.with_connection do |connection|
      query = connection.method(:select_value)
      intercept = lambda do |sql, *args, **kwargs|
        acquired = query.call(sql, *args, **kwargs)
        if sql.include?("pg_try_advisory_lock") && acquired
          Thread.new do
            ResortWeatherMonitor.connection_pool.with_connection do
              ResortWeatherMonitor.find(monitor.id).update!(next_check_at: ANCHOR + 1.day, next_probe_at: ANCHOR + 12.hours)
            end
          end.value
        end
        acquired
      end
      connection.cache do
        ResortWeatherMonitor.find_by(resort_id: @resort.id) # prime this session's query cache
        connection.stub(:select_value, intercept) do
          result = WeatherMonitoring::RunEvaluation.call(resort: @resort, scheduled: true)
          assert result.success?
          assert_equal "not_due", result.value[:code]
          assert_equal false, result.value[:execution][:invoked]
        end
      end
    end
    assert_unlocked_from_another_session
  ensure
    travel_back
  end

  test "scheduled evaluation captures time after lock and overrides caller mode and persistence" do
    travel_to ANCHOR
    ResortWeatherMonitor.create!(resort: @resort, enabled: true)
    ResortWeatherMonitor.connection_pool.with_connection do |connection|
      query = connection.method(:select_value)
      intercept = lambda do |sql, *args, **kwargs|
        acquired = query.call(sql, *args, **kwargs)
        travel_to ANCHOR + 3.minutes if sql.include?("pg_try_advisory_lock") && acquired
        acquired
      end
      WeatherMonitoring::EvaluateResort.expects(:call).with(resort: @resort, persist: true, probe: false,
        evaluation_at: ANCHOR + 3.minutes).returns(success)
      connection.stub(:select_value, intercept) do
        result = WeatherMonitoring::RunEvaluation.call(resort: @resort, scheduled: true, persist: false, probe: true, evaluation_at: ANCHOR - 1.day)
        assert result.success?
        assert_equal "detailed", result.value[:execution][:mode]
        assert_equal ANCHOR + 3.minutes, result.value[:execution][:evaluation_at]
      end
    end
    assert_unlocked_from_another_session
  ensure
    travel_back
  end

  private

  def assert_unlocked_from_another_session
    key = Digest::SHA256.hexdigest("weather_monitoring:resort:#{@resort.id}").first(15).to_i(16)
    available = Thread.new do
      ResortWeatherMonitor.connection_pool.with_connection do |connection|
        acquired = connection.select_value("SELECT pg_try_advisory_lock(#{key})")
        begin
          acquired
        ensure
          connection.select_value("SELECT pg_advisory_unlock(#{key})") if acquired
        end
      end
    end.value
    assert_equal true, available, "lock leaked into the connection pool"
  end
end
