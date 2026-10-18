class AddOrganizationAdministration < ActiveRecord::Migration[8.0]
  def up
    remove_check_constraint :admin_users, name: "admin_users_role_allowed"
    add_check_constraint :admin_users, "role IN ('super_admin', 'canyon_admin', 'mural_admin', 'mahi_tahi_admin', 'organization_admin')", name: "admin_users_role_allowed"
    create_table :whare_pumanawa_organization_memberships do |t|
      t.references :organization, null: false, foreign_key: { to_table: :whare_pumanawa_organizations }
      t.references :admin_user, null: false, foreign_key: { to_table: :admin_users }
      t.timestamps
    end
    add_index :whare_pumanawa_organization_memberships, [ :organization_id, :admin_user_id ], unique: true,
      name: "index_whare_org_memberships_on_org_and_admin"
  end

  def down
    if select_value("SELECT EXISTS (SELECT 1 FROM admin_users WHERE role IN ('mahi_tahi_admin', 'organization_admin'))") ||
        select_value("SELECT EXISTS (SELECT 1 FROM whare_pumanawa_organization_memberships)")
      raise ActiveRecord::IrreversibleMigration, "Reassign new admin roles and remove organization memberships deliberately before rollback."
    end

    drop_table :whare_pumanawa_organization_memberships
    remove_check_constraint :admin_users, name: "admin_users_role_allowed"
    add_check_constraint :admin_users, "role IN ('super_admin', 'canyon_admin', 'mural_admin')", name: "admin_users_role_allowed"
  end
end
