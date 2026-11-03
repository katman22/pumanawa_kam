require "test_helper"
require_relative "../helpers/weather_monitoring_data"

class WeatherAlertSignalTest < ActiveSupport::TestCase
  include WeatherMonitoringData

  setup do
    @resort = pilot_resort
    @observation = WeatherMonitoring::RecordAlertObservations.call(collection: fixture("brighton_alert_signal"), zone_ids: [], seen_at: ANCHOR, signal_evidence: true).value[:records].first
  end

  test "required source type timestamp and unique revision are validated" do
    refute WeatherAlertSignal.new.valid?
    signal = WeatherAlertSignal.create!(weather_alert_observation: @observation, signal_type: "issued", detected_at: ANCHOR)
    refute WeatherAlertSignal.new(weather_alert_observation: @observation, signal_type: "issued", detected_at: ANCHOR).valid?
    refute WeatherAlertSignal.new(weather_alert_observation: @observation, signal_type: "invented", detected_at: ANCHOR).valid?
    assert_raises(ActiveRecord::RecordNotUnique) do
      WeatherAlertSignal.transaction(requires_new: true) do
        WeatherAlertSignal.insert_all!([ { weather_alert_observation_id: @observation.id, signal_type: "issued", detected_at: ANCHOR } ])
      end
    end
    assert_raises(ActiveRecord::InvalidForeignKey) do
      WeatherAlertObservation.transaction(requires_new: true) { WeatherAlertObservation.where(id: @observation.id).delete_all }
    end
    assert_equal @observation.id, signal.reload.weather_alert_observation_id
  end

  test "resort association has required fields and database enforced unique pair" do
    signal = WeatherAlertSignal.create!(weather_alert_observation: @observation, signal_type: "issued", detected_at: ANCHOR)
    refute WeatherAlertSignalResort.new.valid?
    association = WeatherAlertSignalResort.create!(weather_alert_signal: signal, resort: @resort, associated_at: ANCHOR, evidence: { "method" => "test" })
    assert_equal [ @resort.id ], signal.resorts.pluck(:id)
    assert_raises(ActiveRecord::RecordNotUnique) do
      WeatherAlertSignalResort.transaction(requires_new: true) do
        WeatherAlertSignalResort.insert_all!([ association.attributes.except("id") ])
      end
    end
    assert_raises(ActiveRecord::InvalidForeignKey) do
      WeatherAlertSignal.transaction(requires_new: true) { WeatherAlertSignal.where(id: signal.id).delete_all }
    end
  end
end
