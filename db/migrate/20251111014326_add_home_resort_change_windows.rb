# db/migrate/20251110_add_home_resort_change_windows.rb
class AddHomeResortChangeWindows < ActiveRecord::Migration[8.0]
  def change
    create_table :home_resort_change_windows, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true
      # The week “bucket” start in local time (America/Denver) at Sunday 00:00
      t.date :window_start, null: false
      t.integer :changes_used, null: false, default: 0
      t.datetime :last_action_at
      t.timestamps
    end
    add_index :home_resort_change_windows, [ :user_id, :window_start ], unique: true
  end
end
