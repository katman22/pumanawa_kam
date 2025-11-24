# db/migrate/20251110_add_kind_to_home_resorts.rb
class AddKindToHomeResorts < ActiveRecord::Migration[8.0]
  def change
    add_column :home_resorts, :kind, :integer, null: false, default: 0  # 0=subscribed, 1=free
    add_check_constraint :home_resorts, "kind IN (0,1)", name: "home_resorts_kind_check"

    # You already have:
    # add_index :home_resorts, [:user_id, :resort_id], unique: true
  end
end
