# db/migrate/20251111020336_add_home_resort_change_window_to_users.rb
class AddHomeResortChangeWindowToUsers < ActiveRecord::Migration[8.0]
  def up
    add_column :users, :home_resort_window_start, :datetime
    add_column :users, :home_resort_changes_remaining, :integer

    # Initialize a sane window start (current week Sunday 00:00 MST) but
    # leave remaining NULL so the service initializes it on first use per tier.
    tz   = ActiveSupport::TimeZone["America/Denver"]
    wk0  = tz.now.beginning_of_week(:sunday)
    iso  = wk0.utc.iso8601 # avoid to_s(:db)

    execute <<~SQL.squish
      UPDATE users
      SET home_resort_window_start = #{connection.quote(iso)},
          home_resort_changes_remaining = NULL
    SQL
  end

  def down
    remove_column :users, :home_resort_window_start
    remove_column :users, :home_resort_changes_remaining
  end
end
