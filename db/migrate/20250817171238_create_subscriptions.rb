class CreateSubscriptions < ActiveRecord::Migration[7.2]
  def change
    create_table :subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :platform, null: false # ios|android
      t.string  :product_id, null: false # store SKU
      t.string  :status, null: false, default: "active" # active|in_grace|on_hold|canceled|expired
      t.datetime :started_at
      t.datetime :expires_at
      t.datetime :revoked_at
      t.string  :latest_transaction_id
      t.string  :original_transaction_id
      t.boolean :auto_renew, default: true
      t.jsonb   :raw_status, null: false, default: {}
      t.timestamps
    end

    add_index :subscriptions, [:user_id, :platform, :product_id]
    add_index :subscriptions, :latest_transaction_id, unique: true, where: "latest_transaction_id IS NOT NULL"
    add_index :subscriptions, :original_transaction_id
    add_check_constraint :subscriptions, "platform IN ('ios','android')", name: "subscriptions_platform_check"
  end
end
