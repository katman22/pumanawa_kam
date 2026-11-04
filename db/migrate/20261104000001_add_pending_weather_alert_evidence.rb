class AddPendingWeatherAlertEvidence < ActiveRecord::Migration[8.0]
  def change
    add_column :weather_alert_acquisitions, :initial_window_start_at, :datetime
    add_column :weather_alert_acquisitions, :pending_evidence, :jsonb
    add_check_constraint :weather_alert_acquisitions,
      "pending_evidence IS NULL OR jsonb_typeof(pending_evidence) = 'object'", name: "weather_alert_pending_object"
  end
end
