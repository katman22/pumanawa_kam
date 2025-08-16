class AddResorts < ActiveRecord::Migration[8.0]
  def change
    create_table :resorts do |t|
      t.string :resort_name, null: false, limit: 50
      t.string :slug,        null: false, limit: 36 # was resort_id; normalized/slugged
      t.float  :latitude,    null: false
      t.float  :longitude,   null: false
      t.string :departure_point, limit: 80
      t.string :location, limit: 120
      t.boolean :live, default: false
      t.timestamps
    end
    add_index :resorts, :slug, unique: true
    add_index :resorts, :resort_name, unique: true
  end
end
