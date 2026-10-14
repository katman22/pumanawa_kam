class CreateWharePumanawaMurals < ActiveRecord::Migration[8.0]
  def change
    create_table :whare_pumanawa_murals do |t|
      t.string :title, null: false
      t.string :slug, null: false
      t.string :location
      t.integer :year
      t.string :client
      t.text :description
      t.integer :position, null: false, default: 0
      t.boolean :published, null: false, default: false
      t.timestamps
    end

    add_index :whare_pumanawa_murals, :slug, unique: true
    add_check_constraint :whare_pumanawa_murals, "position >= 0", name: "whare_pumanawa_murals_position_nonnegative"
  end
end
