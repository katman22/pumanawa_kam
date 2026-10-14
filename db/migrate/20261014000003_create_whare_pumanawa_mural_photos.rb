class CreateWharePumanawaMuralPhotos < ActiveRecord::Migration[8.0]
  def change
    create_table :whare_pumanawa_mural_photos do |t|
      t.references :mural, null: false, foreign_key: { to_table: :whare_pumanawa_murals }
      t.string :alt_text
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_check_constraint :whare_pumanawa_mural_photos, "position >= 0", name: "whare_pumanawa_mural_photos_position_nonnegative"
  end
end
