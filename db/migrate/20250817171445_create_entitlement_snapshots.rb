class CreateEntitlementSnapshots < ActiveRecord::Migration[7.2]
  def change
    create_table :entitlement_snapshots do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :version, null: false, default: 1
      t.boolean :active, null: false, default: false
      t.string  :tier, null: false, default: "free"
      t.datetime :valid_until
      t.jsonb   :features, null: false, default: []
      t.jsonb   :source,   null: false, default: {} # {reason, provider, id}
      t.timestamps
    end

    add_index :entitlement_snapshots, [:user_id, :created_at]
  end
end
