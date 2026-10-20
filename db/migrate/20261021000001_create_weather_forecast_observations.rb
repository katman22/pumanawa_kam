class CreateWeatherForecastObservations < ActiveRecord::Migration[8.0]
  def change
    create_table :weather_forecast_observations do |t|
      t.references :resort, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :source_key, null: false
      t.datetime :source_updated_at, null: false
      t.datetime :first_fetched_at, null: false
      t.datetime :forecast_window_start, null: false
      t.datetime :forecast_window_end, null: false
      t.string :content_sha256, null: false, limit: 64
      t.integer :normalization_version, null: false
      %i[selected_intervals summary quality source_metadata].each { |column| t.jsonb column, null: false, default: {} }
    end
    add_index :weather_forecast_observations, [ :resort_id, :provider, :source_key, :source_updated_at, :content_sha256, :normalization_version ], unique: true, name: "weather_forecast_revision_unique"
    add_index :weather_forecast_observations, [ :resort_id, :first_fetched_at ], name: "weather_forecast_resort_history"
    add_check_constraint :weather_forecast_observations, "forecast_window_end > forecast_window_start", name: "weather_forecast_valid_window"
    add_check_constraint :weather_forecast_observations, "normalization_version > 0", name: "weather_forecast_version_positive"
  end
end
