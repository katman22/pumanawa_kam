class AddWharePumanawaOrganizations < ActiveRecord::Migration[8.0]
  def up
    create_table :whare_pumanawa_organizations do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :location
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :whare_pumanawa_organizations, :slug, unique: true
    add_check_constraint :whare_pumanawa_organizations, "position >= 0", name: "whare_organizations_position_nonnegative"
    create_table :whare_pumanawa_organization_contributors do |t|
      t.references :organization, null: false, foreign_key: { to_table: :whare_pumanawa_organizations }
      t.references :contributor, null: false, foreign_key: { to_table: :whare_pumanawa_contributors }
      t.timestamps
    end
    add_index :whare_pumanawa_organization_contributors, [ :organization_id, :contributor_id ], unique: true,
      name: "index_whare_org_contributors_on_org_and_contributor"
    add_reference :whare_pumanawa_projects, :organization, null: true, foreign_key: { to_table: :whare_pumanawa_organizations }
    backfill_existing_projects
  end

  def backfill_existing_projects
    execute <<~SQL
      INSERT INTO whare_pumanawa_organizations (name, slug, position, active, created_at, updated_at)
      SELECT 'Existing Hosted Organization', 'existing-hosted-organization', 0, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      WHERE EXISTS (SELECT 1 FROM whare_pumanawa_projects WHERE organization_id IS NULL)
      ON CONFLICT (slug) DO NOTHING
    SQL
    execute <<~SQL
      UPDATE whare_pumanawa_projects
      SET organization_id = (SELECT id FROM whare_pumanawa_organizations WHERE slug = 'existing-hosted-organization')
      WHERE organization_id IS NULL
    SQL
  end

  def down
    remove_reference :whare_pumanawa_projects, :organization, foreign_key: { to_table: :whare_pumanawa_organizations }
    drop_table :whare_pumanawa_organization_contributors
    drop_table :whare_pumanawa_organizations
  end
end
