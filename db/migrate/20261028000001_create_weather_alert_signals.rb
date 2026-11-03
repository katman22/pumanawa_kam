class CreateWeatherAlertSignals < ActiveRecord::Migration[8.0]
  def change
    create_table :weather_alert_signals do |t|
      t.references :weather_alert_observation, null: false, foreign_key: true, index: { unique: true, name: "weather_signal_observation_unique" }
      t.references :previous_observation, foreign_key: { to_table: :weather_alert_observations }, index: { name: "weather_signal_previous" }
      t.string :signal_type, null: false
      t.datetime :detected_at, null: false
      t.jsonb :changes, null: false, default: {}
    end
    add_check_constraint :weather_alert_signals,
      "signal_type IN ('issued', 'updated', 'corrected', 'cancelled', 'material_content_changed')", name: "weather_signal_type_valid"
    add_index :weather_alert_signals, :detected_at

    create_table :weather_alert_signal_resorts do |t|
      t.references :weather_alert_signal, null: false, foreign_key: true, index: false
      t.references :resort, null: false, foreign_key: true
      t.datetime :associated_at, null: false
      t.jsonb :evidence, null: false, default: {}
    end
    add_index :weather_alert_signal_resorts, [ :weather_alert_signal_id, :resort_id ], unique: true, name: "weather_signal_resort_unique"
  end
end
