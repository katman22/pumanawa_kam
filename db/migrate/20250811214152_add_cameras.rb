class AddCameras < ActiveRecord::Migration[8.0]
  def change
    create_table :cameras do |t|
      t.references :resort, null: false, foreign_key: true
      t.boolean :always_show, default: false
      t.string :name
      t.string :type, null: false
      t.string :uri, null: false
      t.integer :type_id, null: false
    end
  end
end
