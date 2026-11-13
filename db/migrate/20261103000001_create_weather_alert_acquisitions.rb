class CreateWeatherAlertAcquisitions < ActiveRecord::Migration[8.0]
  def change
    create_table :weather_alert_acquisitions do |t|
      t.string :provider, null: false, default: "noaa"
      t.string :scope_key, null: false
      t.jsonb :query, null: false, default: {}
      t.boolean :enabled, null: false, default: false
      %i[last_attempt_at last_success_at covered_from_at covered_through_at next_check_at lease_expires_at].each { |name| t.datetime name }
      t.uuid :lease_token
      t.integer :consecutive_failures, null: false, default: 0
      t.string :last_error_code
      t.jsonb :coverage_gaps, null: false, default: []
      t.jsonb :last_result, null: false, default: {}
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :weather_alert_acquisitions, [ :provider, :scope_key ], unique: true, name: "weather_alert_scope_unique"
    add_index :weather_alert_acquisitions, [ :enabled, :next_check_at ], name: "weather_alert_acquisition_due"
    add_check_constraint :weather_alert_acquisitions, "consecutive_failures >= 0", name: "weather_alert_failures_nonnegative"
    add_check_constraint :weather_alert_acquisitions, "(lease_token IS NULL) = (lease_expires_at IS NULL)", name: "weather_alert_lease_pair"
    add_check_constraint :weather_alert_acquisitions, "jsonb_typeof(coverage_gaps) = 'array'", name: "weather_alert_gaps_array"
  end
end
