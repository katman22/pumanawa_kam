class RemoveUniqueEntitlementSnapshotFingerprint < ActiveRecord::Migration[7.2]
  def change
    # Remove the unique index if it exists
    if index_exists?(:entitlement_snapshots, [:user_id, :fingerprint], unique: true, name: "idx_unique_entitlement_snapshots_user_fp")
      remove_index :entitlement_snapshots, name: "idx_unique_entitlement_snapshots_user_fp"
    end

    # Re-add as NON-unique index (optional but recommended)
    unless index_exists?(:entitlement_snapshots, [:user_id, :fingerprint])
      add_index :entitlement_snapshots, [:user_id, :fingerprint]
    end
  end
end