class CreateAdminUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :admin_users do |t|
      t.string :username, null: false
      t.string :password_digest, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :admin_users, :username, unique: true
    add_check_constraint :admin_users, "username = lower(btrim(username)) AND length(username) > 0", name: "admin_users_username_normalized"
    add_check_constraint :admin_users, "length(password_digest) > 0", name: "admin_users_password_digest_present"
  end
end
