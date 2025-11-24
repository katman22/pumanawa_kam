class CreateEntitlementOverrides < ActiveRecord::Migration[8.0]
  def change
    create_table :entitlement_overrides, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true
      t.string   :entitlement, null: false      # "premium"|"pro"|"standard"
      t.datetime :starts_at,   null: false
      t.datetime :ends_at
      t.string   :reason
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :entitlement_overrides, [ :user_id, :starts_at ]
  end
end
