class CreateReceipts < ActiveRecord::Migration[7.2]
  def change
    create_table :receipts do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :platform, null: false # ios|android
      t.string  :product_id, null: false
      t.string  :transaction_id, null: false
      t.text    :token, null: false # store purchase token / signedTxn
      t.jsonb   :raw_json, null: false, default: {}
      t.timestamps
    end

    add_index :receipts, :transaction_id, unique: true
    add_check_constraint :receipts, "platform IN ('ios','android')", name: "receipts_platform_check"
  end
end
