class AddWharePumanawaProjects < ActiveRecord::Migration[8.0]
  def up
    create_table :whare_pumanawa_projects do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :location
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :whare_pumanawa_projects, :slug, unique: true
    add_check_constraint :whare_pumanawa_projects, "position >= 0", name: "whare_projects_position_nonnegative"
    create_table :whare_pumanawa_project_memberships do |t|
      t.references :project, null: false, foreign_key: { to_table: :whare_pumanawa_projects }
      t.references :admin_user, null: false, foreign_key: { to_table: :admin_users }
      t.timestamps
    end
    add_index :whare_pumanawa_project_memberships, [ :project_id, :admin_user_id ], unique: true,
      name: "index_whare_project_memberships_on_project_and_admin"
    add_reference :whare_pumanawa_murals, :project, null: true,
      foreign_key: { to_table: :whare_pumanawa_projects }
    backfill_existing_murals
    grant_initial_memberships
  end

  def backfill_existing_murals
    execute <<~SQL
      INSERT INTO whare_pumanawa_projects (name, slug, position, active, created_at, updated_at)
      SELECT 'Whare Pūmanawa Collection', 'whare-pumanawa-collection', 0, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      WHERE EXISTS (SELECT 1 FROM whare_pumanawa_murals WHERE project_id IS NULL)
      ON CONFLICT (slug) DO NOTHING
    SQL
    execute <<~SQL
      UPDATE whare_pumanawa_murals
      SET project_id = (SELECT id FROM whare_pumanawa_projects WHERE slug = 'whare-pumanawa-collection')
      WHERE project_id IS NULL
    SQL
  end

  # One-time rollout grant to existing mural admins, never an account callback.
  def grant_initial_memberships
    execute <<~SQL
      INSERT INTO whare_pumanawa_project_memberships (project_id, admin_user_id, created_at, updated_at)
      SELECT projects.id, admins.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM whare_pumanawa_projects projects CROSS JOIN admin_users admins
      WHERE projects.slug = 'whare-pumanawa-collection' AND admins.role = 'mural_admin'
      ON CONFLICT (project_id, admin_user_id) DO NOTHING
    SQL
  end

  def down
    remove_reference :whare_pumanawa_murals, :project, foreign_key: { to_table: :whare_pumanawa_projects }
    drop_table :whare_pumanawa_project_memberships
    drop_table :whare_pumanawa_projects
  end
end
