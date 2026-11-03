class RenameWeatherAlertSignalChanges < ActiveRecord::Migration[8.0]
  def change
    rename_column :weather_alert_signals, :changes, :change_details
  end
end
