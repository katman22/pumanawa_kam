class AddWharePumanawaContributors < ActiveRecord::Migration[8.0]
  def up
    create_table :whare_pumanawa_contributors do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :bio
      t.string :location
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :whare_pumanawa_contributors, :slug, unique: true
    add_check_constraint :whare_pumanawa_contributors, "position >= 0", name: "whare_contributors_position_nonnegative"
    add_reference :whare_pumanawa_murals, :contributor, null: true,
      foreign_key: { to_table: :whare_pumanawa_contributors }
    backfill_existing_murals
  end

  # SQL deliberately avoids application callbacks and does not touch mural content,
  # slugs, publication state, timestamps, photos or storage records.
  def backfill_existing_murals
    execute <<~SQL
      INSERT INTO whare_pumanawa_contributors (name, slug, position, active, created_at, updated_at)
      SELECT 'Whare Pūmanawa', 'whare-pumanawa', 0, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      WHERE EXISTS (SELECT 1 FROM whare_pumanawa_murals WHERE contributor_id IS NULL)
      ON CONFLICT (slug) DO NOTHING
    SQL
    execute <<~SQL
      UPDATE whare_pumanawa_murals
      SET contributor_id = (SELECT id FROM whare_pumanawa_contributors WHERE slug = 'whare-pumanawa')
      WHERE contributor_id IS NULL
    SQL
  end

  def down
    remove_reference :whare_pumanawa_murals, :contributor, foreign_key: { to_table: :whare_pumanawa_contributors }
    drop_table :whare_pumanawa_contributors
  end
end
