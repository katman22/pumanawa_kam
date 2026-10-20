class CreateResortWeatherMonitors < ActiveRecord::Migration[8.0]
  def change
    create_table :resort_weather_monitors do |t|
      t.references :resort, null: false, foreign_key: true, index: { unique: true }
      t.string :provider, null: false, default: "noaa"
      t.boolean :enabled, null: false, default: false
      %i[next_check_at next_probe_at last_checked_at last_success_at last_source_updated_at mapping_checked_at acceleration_until last_error_at last_alert_checked_at].each { |column| t.datetime column }
      t.references :current_forecast_observation, foreign_key: { to_table: :weather_forecast_observations }, index: { name: "weather_monitor_current_forecast" }
      t.jsonb :mapping, null: false, default: {}
      t.jsonb :last_decision, null: false, default: {}
      t.jsonb :active_alert_identifiers, null: false, default: []
      t.string :monitoring_level
      t.string :last_error_code
      t.integer :failure_count, null: false, default: 0
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :resort_weather_monitors, [ :enabled, :next_check_at ]
    add_index :resort_weather_monitors, [ :enabled, :next_probe_at ]
    add_check_constraint :resort_weather_monitors, "failure_count >= 0", name: "weather_monitor_failures_nonnegative"
  end
end
