class CreateProductCatalogs < ActiveRecord::Migration[7.2]
  def change
    create_table :product_catalogs do |t|
      t.string  :name, null: false
      t.string  :tier, null: false, default: "premium"
      t.string  :external_id_ios
      t.string  :external_id_android
      t.boolean :is_addon, null: false, default: false
      t.jsonb   :feature_flags, null: false, default: []
      t.string  :status, null: false, default: "active" # active|deprecated
      t.datetime :valid_from
      t.datetime :valid_to
      t.timestamps
    end

    add_index :product_catalogs, :name, unique: true
    add_index :product_catalogs, :external_id_ios, unique: true, where: "external_id_ios IS NOT NULL"
    add_index :product_catalogs, :external_id_android, unique: true, where: "external_id_android IS NOT NULL"
  end
end
