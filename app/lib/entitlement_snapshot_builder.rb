class EntitlementSnapshotBuilder
  def self.write!(user:, entitlements:)
    fingerprint = Digest::SHA256.hexdigest(entitlements.to_json)

    EntitlementSnapshot.create!(
      user:        user,
      version:     entitlements[:version],
      active:      entitlements[:active],
      tier:        entitlements[:tier],
      valid_until: entitlements[:valid_until],
      features:    entitlements[:features],
      source:      entitlements[:sources],
      fingerprint: fingerprint
    )
  end
end
