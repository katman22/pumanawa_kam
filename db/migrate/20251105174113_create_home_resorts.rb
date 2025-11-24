# db/migrate/20251110_add_kind_to_home_resorts.rb
class CreateHomeResorts < ActiveRecord::Migration[8.0]
  def change
    create_table :home_resorts, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true
      t.references :resort, null: false, foreign_key: true
      t.timestamps
    end
    add_index :home_resorts, [ :user_id, :resort_id ], unique: true
    add_column :home_resorts, :kind, :integer, null: false, default: 0  # 0=subscribed, 1=free
    add_check_constraint :home_resorts, "kind IN (0,1)", name: "home_resorts_kind_check"
  end
end
