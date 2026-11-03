require "test_helper"
require_relative "../../helpers/weather_monitoring_data"

class WeatherAlertSignalConcurrencyTest < ActiveSupport::TestCase
  include WeatherMonitoringData
  self.use_transactional_tests = false

  setup do
    @resort = pilot_resort
    mapping = fixture("brighton_points")["properties"].merge("latitude" => @resort.latitude, "longitude" => @resort.longitude)
    @monitor = ResortWeatherMonitor.create!(resort: @resort, enabled: true, mapping: mapping)
    @record = WeatherMonitoring::RecordAlertObservations.call(collection: fixture("brighton_alert_signal"), zone_ids: [], seen_at: ANCHOR, signal_evidence: true).value[:records].first
    HTTParty.stubs(:get).raises("Unexpected live NOAA request")
  end

  teardown do
    ids = WeatherAlertSignal.where(weather_alert_observation_id: @record.id).pluck(:id)
    WeatherAlertSignalResort.where(weather_alert_signal_id: ids).delete_all
    WeatherAlertSignal.where(id: ids).delete_all
    WeatherAlertObservation.where(id: @record.id).delete_all
    ResortWeatherMonitor.where(id: @monitor.id).delete_all
    Resort.where(id: @resort.id).delete_all
  end

  test "two database sessions cannot duplicate a source signal or its resort association" do
    ready, start, results = Queue.new, Queue.new, Queue.new
    workers = 2.times.map do
      Thread.new do
        ResortWeatherMonitor.connection_pool.with_connection do
          ready << true
          start.pop
          results << WeatherMonitoring::GenerateAlertSignals.call(observations: [ @record.id ], detected_at: ANCHOR)
        end
      rescue StandardError => error
        results << error
      end
    end
    2.times { Timeout.timeout(10) { ready.pop } }
    2.times { start << true }
    outcomes = 2.times.map { Timeout.timeout(10) { results.pop } }
    outcomes.each do |outcome|
      raise outcome if outcome.is_a?(Exception)

      assert outcome.success?, outcome.value.inspect
    end
    assert_equal [ 0, 1 ], outcomes.map { |outcome| outcome.value[:created_count] }.sort
    assert_equal 1, WeatherAlertObservation.count
    assert_equal 1, WeatherAlertSignal.count
    assert_equal 1, WeatherAlertSignalResort.count
  ensure
    2.times { start << true } if start
    workers&.each { |worker| worker.join(10) }
  end
end
