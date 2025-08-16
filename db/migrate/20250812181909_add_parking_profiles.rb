class AddParkingProfiles < ActiveRecord::Migration[7.2]
  def change
    create_table :parking_profiles do |t|
      t.references :resort, null: false, foreign_key: true
      t.string :label, null: true, limit: 50
      t.string :season, null: false, limit: 120
      t.datetime :effective_from
      t.datetime :effective_to
      t.boolean :overnight, default: false
      t.integer :version, null: false, default: 1
      t.jsonb :rules, null: false, default: []
      t.jsonb :faqs, null: false, default: []
      t.jsonb :operations, null: false, default: {}
      t.jsonb :highway_parking, null: false, default: {}
      t.jsonb :links, null: false, default: []
      t.jsonb :accessibility, null: false, default: {}
      t.jsonb :media, null: false, default: {}
      t.jsonb :sources, null: false, default: []
      t.string :summary
      t.string :source_digest
      t.string :updated_by, limit: 120
      t.timestamps
    end
    add_index :parking_profiles, [ :resort_id, :season ], unique: true
    add_index :parking_profiles, :effective_from
    add_index :parking_profiles, :effective_to
  end
end
