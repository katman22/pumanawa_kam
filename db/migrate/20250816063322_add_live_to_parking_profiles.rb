class AddLiveToParkingProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :parking_profiles, :live, :boolean, default: false, null: false
  end
end
