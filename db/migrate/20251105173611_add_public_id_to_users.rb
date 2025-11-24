class AddPublicIdToUsers < ActiveRecord::Migration[8.0]
  def change
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")
    add_column :users, :public_id, :uuid, default: "gen_random_uuid()", null: false
    add_index  :users, :public_id, unique: true
  end
end
