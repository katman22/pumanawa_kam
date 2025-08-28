class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string  :email                           # allow NULL for Apple “Hide My Email” or no-email providers
      t.string  :display_name
      t.string  :locale,     null: false, default: "en"
      t.string  :time_zone,  null: false, default: "America/Denver"
      t.string  :role,       null: false, default: "user"    # user|admin
      t.string  :status,     null: false, default: "active"  # active|disabled
      t.datetime :last_sign_in_at
      t.datetime :deleted_at                       # soft delete (optional)
      t.jsonb :metadata,   null: false, default: {} # non-PII prefs, e.g. { theme: "dark" }
      t.timestamps
    end

    add_index :users, :email, unique: true, where: "email IS NOT NULL"
    add_index :users, :status
    add_index :users, :role
  end
end
