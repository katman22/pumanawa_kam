# db/migrate/20251105_add_fingerprint_to_entitlement_snapshots.rb
class AddFingerprintToEntitlementSnapshots < ActiveRecord::Migration[8.0]
  def change
    add_column :entitlement_snapshots, :fingerprint, :string

    # Ensure we don’t create duplicate snapshots for the same user+state.
    # Partial unique index (ignore NULLs so old rows are fine).
    add_index :entitlement_snapshots,
              [ :user_id, :fingerprint ],
              unique: true,
              where: "fingerprint IS NOT NULL",
              name: "idx_unique_entitlement_snapshots_user_fp"
  end
end
