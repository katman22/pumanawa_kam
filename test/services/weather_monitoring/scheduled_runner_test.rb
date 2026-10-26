require "test_helper"
require_relative "../../helpers/weather_monitoring_data"

class WeatherMonitoringScheduledRunnerTest < ActiveSupport::TestCase
  include WeatherMonitoringData
  self.use_transactional_tests = false

  setup do
    travel_to ANCHOR
    @resort = pilot_resort
    @resort_ids = [ @resort.id ]
    HTTParty.stubs(:get).raises("Unexpected live NOAA request")
  end

  teardown do
    travel_back
    ResortWeatherMonitor.where(resort_id: @resort_ids).delete_all
    WeatherForecastObservation.where(resort_id: @resort_ids).delete_all
    Resort.where(id: @resort_ids).delete_all
  end

  def monitor(**attributes)
    @monitor ||= ResortWeatherMonitor.create!(resort: @resort, enabled: true,
      next_check_at: ANCHOR - 1.minute, next_probe_at: ANCHOR + 12.hours)
    @monitor.reload.update!(**attributes) if attributes.any?
    @monitor
  end

  def schedule
    WeatherMonitoring::ScheduledRunner.call(run_id: "scheduled-test")
  end

  def evaluation(quality: "complete", alerts: "available")
    ServiceResult.new(success: true, value: { snapshot: { "quality" => { "state" => quality } },
      alerts: { state: alerts }, observation: "existing", source_updated_at: ANCHOR.iso8601,
      cadence: { "next_check_at" => ANCHOR + 6.hours, "next_probe_at" => ANCHOR + 12.hours } })
  end

  def assert_no_work
    WeatherMonitoring::RunEvaluation.expects(:call).never
    before = @resort.attributes
    assert_no_difference [ "ResortWeatherMonitor.count", "WeatherForecastObservation.count" ] do
      result = schedule
      assert result.success?, result.value.inspect
      assert_equal 0, result.value[:candidate_count]
      assert_equal 0, result.value[:invoked_count]
      assert_equal [], result.value[:outcomes]
    end
    assert_equal before, @resort.reload.attributes
  end

  test "no configured monitors is a successful no op without acquisition or creation" do
    assert_no_work
  end

  test "future deadlines and disabled monitors are excluded" do
    monitor(next_check_at: ANCHOR + 1.hour, next_probe_at: ANCHOR + 2.hours)
    assert_no_work
    WeatherMonitoring::RunEvaluation.unstub(:call)
    monitor(enabled: false, next_check_at: nil, next_probe_at: nil)
    assert_no_work
  end

  test "unsupported resorts and non NOAA providers are excluded" do
    other = Resort.create!(resort_name: "Scheduled test other", slug: "scheduled-test-other", latitude: 40, longitude: -111)
    @resort_ids << other.id
    ResortWeatherMonitor.create!(resort: other, enabled: true)
    monitor.update_columns(provider: "other")
    assert_no_work
  end

  test "due and NULL deadlines choose detailed before probe exactly once" do
    [ [ ANCHOR, ANCHOR + 1.hour, false ], [ ANCHOR + 1.hour, ANCHOR, true ],
      [ ANCHOR, ANCHOR, false ], [ nil, ANCHOR + 1.hour, false ],
      [ ANCHOR + 1.hour, nil, true ], [ nil, nil, false ] ].each do |check, probe_at, probe|
      monitor(next_check_at: check, next_probe_at: probe_at)
      WeatherMonitoring::EvaluateResort.expects(:call).once.with(resort: @resort, persist: true, probe: probe, evaluation_at: ANCHOR).returns(evaluation)
      result = schedule
      assert result.success?, result.value.inspect
      assert_equal "scheduled-test", result.value[:run_id]
      assert_equal ANCHOR, result.value[:started_at]
      assert_equal ANCHOR, result.value[:completed_at]
      assert_equal 1, result.value[:candidate_count]
      assert_equal 1, result.value[:invoked_count]
      assert_equal 1, result.value[:successful_count]
      assert_equal 0, result.value[:skipped_count]
      assert_equal 0, result.value[:failed_count]
      assert_equal 0, result.value[:degraded_count]
      assert_equal probe ? "probe" : "detailed", result.value[:outcomes].first[:mode]
    end
  end

  test "rate limit backoff overrides old detailed deadline and resumes at equality" do
    monitor(last_error_code: "rate_limited", next_check_at: ANCHOR - 1.day, next_probe_at: ANCHOR + 1.hour)
    WeatherMonitoring::EvaluateResort.expects(:call).never
    result = schedule
    assert result.success?
    assert_equal 0, result.value[:invoked_count]
    assert_equal 1, result.value[:skipped_count]
    assert_equal "rate_limited", result.value[:outcomes].first[:reason]
    assert_equal ANCHOR + 1.hour, result.value[:outcomes].first[:retry_at]
    WeatherMonitoring::EvaluateResort.unstub(:call)
    travel_to ANCHOR + 1.hour
    WeatherMonitoring::EvaluateResort.expects(:call).with(resort: @resort, persist: true, probe: false, evaluation_at: ANCHOR + 1.hour).returns(evaluation)
    assert_equal 1, schedule.value[:invoked_count]
  end

  test "candidate changed just before acquisition is reloaded under lock and skipped" do
    monitor
    original = WeatherMonitoring::RunEvaluation.method(:call)
    replacement = lambda do |**options|
      ResortWeatherMonitor.find(@monitor.id).update!(next_check_at: ANCHOR + 1.day, next_probe_at: ANCHOR + 12.hours)
      travel_to ANCHOR + 1.minute
      original.call(**options)
    end
    WeatherMonitoring::EvaluateResort.expects(:call).never
    ResortWeatherMonitor.cache do
      WeatherMonitoring::RunEvaluation.stub(:call, replacement) do
        result = schedule
        assert result.success?
        assert_equal 1, result.value[:candidate_count]
        assert_equal 1, result.value[:skipped_count]
        assert_equal "not_due", result.value[:outcomes].first[:reason]
        assert_equal ANCHOR + 1.minute, result.value[:outcomes].first[:evaluation_at]
      end
    end
  end

  test "disabled missing or unsupported candidate is rechecked inside guard" do
    [ :disabled, :missing, :unsupported ].each do |change|
      @monitor = nil if change == :unsupported
      monitor
      original = WeatherMonitoring::RunEvaluation.method(:call)
      replacement = lambda do |**options|
        case change
        when :disabled then ResortWeatherMonitor.find(@monitor.id).update!(enabled: false)
        when :missing then ResortWeatherMonitor.find(@monitor.id).destroy!
        when :unsupported then Resort.find(@resort.id).update!(slug: "no-longer-pilot")
        end
        original.call(**options)
      end
      WeatherMonitoring::EvaluateResort.expects(:call).never
      WeatherMonitoring::RunEvaluation.stub(:call, replacement) do
        result = schedule
        assert result.success?
        assert_equal 1, result.value[:skipped_count]
        expected = { disabled: "monitor_disabled", missing: "monitor_missing", unsupported: "pilot_resorts_only" }.fetch(change)
        assert_equal expected, result.value[:outcomes].first[:reason]
      end
      @monitor = nil
      ResortWeatherMonitor.where(resort_id: @resort.id).delete_all
    end
  end

  test "evaluation time is captured after acquisition and outside transaction" do
    monitor
    original = WeatherMonitoring::RunEvaluation.method(:call)
    replacement = lambda do |**options|
      travel_to ANCHOR + 2.minutes
      original.call(**options)
    end
    WeatherMonitoring::EvaluateResort.expects(:call).with do |**options|
      assert_equal ANCHOR + 2.minutes, options[:evaluation_at]
      refute ResortWeatherMonitor.connection_pool.with_connection(&:transaction_open?)
      true
    end.returns(evaluation)
    WeatherMonitoring::RunEvaluation.stub(:call, replacement) do
      assert_equal ANCHOR + 2.minutes, schedule.value[:outcomes].first[:evaluation_at]
    end
  end

  test "real changed probe leaves newly due detailed work to the next invocation" do
    monitor
    mapping = fixture("brighton_points")["properties"].merge("latitude" => @resort.latitude, "longitude" => @resort.longitude)
    raw = fixture("brighton_grid")
    Noaa::Forecast::Point.stubs(:call).returns(ServiceResult.new(success: true, value: mapping))
    Noaa::Alerts::Fetch.stubs(:call).returns(ServiceResult.new(success: true, value: { "features" => [] }))
    Noaa::Forecast::GridData.stubs(:call).returns(ServiceResult.new(success: true, value: { "status" => 200, "body" => raw, "headers" => {} }))
    assert schedule.success?
    monitor(next_probe_at: ANCHOR)
    raw["properties"]["snowfallAmount"]["values"][14]["value"] += 1
    Noaa::Forecast::GridData.expects(:call).once.returns(ServiceResult.new(success: true, value: { "status" => 200, "body" => raw, "headers" => {} }))
    result = schedule
    assert result.success?
    assert_equal 1, result.value[:invoked_count]
    assert_equal "probe", result.value[:outcomes].first[:mode]
    assert_equal ANCHOR, @monitor.reload.next_check_at
    Noaa::Forecast::GridData.unstub(:call)
    Noaa::Forecast::GridData.expects(:call).once.returns(ServiceResult.new(success: true, value: { "status" => 200, "body" => raw, "headers" => {} }))
    assert_equal "detailed", schedule.value[:outcomes].first[:mode]
  end

  test "partial unknown and degraded alerts are successful but explicitly degraded" do
    monitor
    [ [ "partial", "available" ], [ "unknown", "available" ], [ "complete", "degraded" ] ].each do |quality, alerts|
      WeatherMonitoring::EvaluateResort.expects(:call).returns(evaluation(quality: quality, alerts: alerts))
      result = schedule
      assert result.success?
      assert_equal 1, result.value[:successful_count]
      assert_equal 1, result.value[:degraded_count]
      assert_equal quality, result.value[:outcomes].first[:quality]
      assert_equal alerts, result.value[:outcomes].first[:alert_state]
      refute result.value.to_json.include?("selected_intervals")
    end
  end

  test "actual acquisition rate limit and exceptions remain failed invoked evaluations" do
    monitor
    WeatherMonitoring::EvaluateResort.expects(:call).returns(ServiceResult.new(success: false, value: { code: "rate_limited", details: "PRIVATE BODY" }))
    result = schedule
    assert result.failure?
    assert_equal 1, result.value[:invoked_count]
    assert_equal 1, result.value[:failed_count]
    assert_equal "rate_limited", result.value[:outcomes].first[:reason]
    refute_includes result.value.to_json, "PRIVATE BODY"
    WeatherMonitoring::EvaluateResort.expects(:call).raises(ArgumentError, "PRIVATE ERROR")
    result = schedule
    assert result.failure?
    assert_equal 1, result.value[:invoked_count]
    assert_equal "unexpected_error", result.value[:outcomes].first[:reason]
    refute_includes result.value.to_json, "PRIVATE ERROR"
    WeatherMonitoring::EvaluateResort.expects(:call).returns(evaluation)
    assert schedule.success?, "exception must release the guard"
  end

  test "runner operational errors return a failed summary" do
    WeatherMonitoring::RunEvaluation.expects(:call).never
    runner = WeatherMonitoring::ScheduledRunner.new(run_id: "query-failure")
    runner.expects(:candidates).raises(ActiveRecord::StatementInvalid, "PRIVATE SQL")
    result = runner.call
    assert result.failure?
    assert_equal "query-failure", result.value[:run_id]
    assert_equal "scheduler_error", result.value[:errors].first[:code]
    assert_equal ANCHOR, result.value[:completed_at]
    refute_includes result.value.to_json, "PRIVATE SQL"
  end

  test "failure does not stop a later independent candidate" do
    first = monitor
    other = Resort.create!(resort_name: "Future scheduler fixture", slug: "future-scheduler-fixture", latitude: 40, longitude: -111)
    @resort_ids << other.id
    second = ResortWeatherMonitor.create!(resort: other, enabled: true)
    runner = WeatherMonitoring::ScheduledRunner.new
    # Production still selects Brighton only. Inject candidates and guard results
    # here solely to exercise serial continuation for a future approved rollout.
    runner.stubs(:candidates).returns([ first, second ])
    execution = { invoked: true, mode: "detailed", evaluation_at: ANCHOR }
    WeatherMonitoring::RunEvaluation.expects(:call).with(resort: @resort, scheduled: true)
      .returns(ServiceResult.new(success: false, value: { code: "transport_error", execution: execution }))
    WeatherMonitoring::RunEvaluation.expects(:call).with(resort: other, scheduled: true)
      .returns(ServiceResult.new(success: true, value: evaluation.value.merge(execution: execution)))
    result = runner.call
    assert result.failure?
    assert_equal 2, result.value[:candidate_count]
    assert_equal 2, result.value[:invoked_count]
    assert_equal 1, result.value[:failed_count]
    assert_equal 1, result.value[:successful_count]
    assert_equal %w[failed successful], result.value[:outcomes].map { |outcome| outcome[:status] }
  end

  test "manual evaluation blocks a scheduled evaluation without duplicate acquisition" do
    assert_concurrent_skip(scheduled: false)
  end

  test "concurrent scheduled runs do not duplicate acquisition" do
    assert_concurrent_skip(scheduled: true)
  end

  private

  def assert_concurrent_skip(scheduled:)
    monitor
    entered, release, results, calls = Queue.new, Queue.new, Queue.new, Queue.new
    worker = nil
    replacement = lambda do |**_options|
      calls << true
      entered << true
      release.pop
      evaluation
    end
    WeatherMonitoring::EvaluateResort.stub(:call, replacement) do
      worker = Thread.new do
        results << if scheduled
          schedule
        else
          WeatherMonitoring::RunEvaluation.call(resort: @resort, persist: true)
        end
      rescue StandardError => error
        results << error
      end
      Timeout.timeout(10) { entered.pop }
      result = schedule
      assert result.success?
      assert_equal 1, result.value[:candidate_count]
      assert_equal 0, result.value[:invoked_count]
      assert_equal 1, result.value[:skipped_count]
      assert_equal "evaluation_busy", result.value[:outcomes].first[:reason]
      release << true
      first = Timeout.timeout(10) { results.pop }
      raise first if first.is_a?(Exception)

      assert first.success?, first.value.inspect
      assert_equal 1, calls.size
      worker.join
    end
  ensure
    release << true if release
    worker&.join(10)
  end
end
