class CreateIdentities < ActiveRecord::Migration[8.0]
  def change
    create_table :identities do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :provider, null: false          # "google" | "apple"
      t.string  :uid,      null: false          # provider user id / sub
      t.string  :email                              # provider email can be nil
      t.jsonb   :raw,      null: false, default: {} # untrusted provider payload, for audit only
      t.timestamps
    end

    add_index :identities, [:provider, :uid], unique: true
    add_index :identities, :email
  end
end
