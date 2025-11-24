# db/migrate/20251110_add_kind_to_home_resorts.rb
class AddKindToHomeResorts < ActiveRecord::Migration[8.0]
  def up
    # add_column :home_resorts, :kind, :integer, null: false, default: 1 # 1 = free, 0 = subscribed
    #
    # # Ensure validity at the DB level
    # add_check_constraint :home_resorts, "kind IN (0,1)", name: "home_resorts_kind_check"
    #
    # # Fast counts per user/kind for limits & UI
    # add_index :home_resorts, [ :user_id, :kind ], name: "index_home_resorts_on_user_id_and_kind"
  end

  def down
    # remove_index :home_resorts, name: "index_home_resorts_on_user_id_and_kind"
    # remove_check_constraint :home_resorts, name: "home_resorts_kind_check"
    # remove_column :home_resorts, :kind
  end
end
