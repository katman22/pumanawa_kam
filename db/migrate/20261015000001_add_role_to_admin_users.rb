class AddRoleToAdminUsers < ActiveRecord::Migration[8.0]
  def up
    add_column :admin_users, :role, :string
    execute "UPDATE admin_users SET role = 'super_admin'"
    change_column_null :admin_users, :role, false
    change_column_default :admin_users, :role, "mural_admin"
    add_check_constraint :admin_users, "role IN ('super_admin', 'canyon_admin', 'mural_admin')", name: "admin_users_role_allowed"
  end

  def down
    remove_column :admin_users, :role
  end
end
