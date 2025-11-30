class Api::V1::IapController < Api::V1::MobileApiController
  def sync
    incoming = params.fetch(:entitlements, {})

    # STEP 1 — Normalize RC purchases → unified entitlement state
    normalized_result = Iap::RevenueCat::SyncPurchases
                          .new(user: current_user, entitlements: incoming)
                          .call
    normalized = normalized_result.value

    # Extract new tier
    new_tier = normalized[:tier]

    # STEP 2 — Determine previous tier
    last_snapshot = EntitlementSnapshot.where(user_id: current_user.id)
                                       .order(created_at: :desc)
                                       .first
    last_tier = last_snapshot&.tier || "free"

    # Helper for ranking tiers
    tier_rank = { "free" => 0, "standard" => 1, "pro" => 2, "premium" => 3 }

    # STEP 3 — Detect tier transition
    is_downgrade = tier_rank[new_tier] < tier_rank[last_tier]

    # STEP 5 — If DOWNGRADE → enforce new limits
    HomeResort.for_user(current_user).subscribed_only.delete_all if is_downgrade

    # STEP 6 — Write snapshot AFTER cleanup
    EntitlementSnapshotBuilder.write!(
      user: current_user,
      entitlements: normalized
    )

    # STEP 7 — Return normalized purchase state to client
    render json: { status: "ok", entitlements: normalized }
  end
end
