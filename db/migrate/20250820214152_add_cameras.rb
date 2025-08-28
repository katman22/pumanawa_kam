class AddCameras < ActiveRecord::Migration[8.0]
  def change
    create_table :cameras do |t|
      t.references :resort, null: false, foreign_key: true
      t.string  :name, null: false
      t.string  :kind, null: false, limit: 32 # "parking" | "traffic"
      t.boolean :show, null: false, default: false
      t.boolean :featured, null: false, default: false   # useful to pin “always show” cams
      t.integer :position, null: false, default: 0       # ordering within a resort/kind
      t.jsonb   :data, null: false, default: {}          # provider payload, urls, etc.
      t.decimal :latitude,  precision: 9, scale: 6   # ~0.11m precision
      t.decimal :longitude, precision: 9, scale: 6
      t.integer :bearing                              # degrees 0..359 (camera view dir), optional
      t.string  :road                                  # e.g. "SR-190" (optional)
      t.string  :jurisdiction
      t.timestamps
    end

    add_index :cameras, [ :resort_id, :kind, :position ]
    add_index :cameras, :show, where: "show = true"
    add_index :cameras, [ :resort_id, :kind, :show ]
    add_index :cameras, [ :resort_id, :kind, :featured ], where: "featured = true"
    add_index :cameras, [ :resort_id, :kind, :name ], unique: true
    add_index :cameras, [ :latitude, :longitude ]
    add_index :cameras, :bearing
  end
end
