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
    is_upgrade   = tier_rank[new_tier] > tier_rank[last_tier]
    is_downgrade = tier_rank[new_tier] < tier_rank[last_tier]

    # STEP 4 — If UPGRADE → wipe homes & reset quotas
    if is_upgrade
      HomeResort.where(user_id: current_user.id).delete_all
      current_user.update!(
        home_resort_window_start: nil,
        home_resort_changes_remaining: nil
      )
    end

    # STEP 5 — If DOWNGRADE → enforce new limits
    if is_downgrade
      allowed = case new_tier
      when "free"     then 1
      when "standard" then 2
      when "pro"      then 4
      when "premium"  then 4
      else 1
      end

      resorts = HomeResort.where(user_id: current_user.id).order(:id)

      if resorts.count > allowed
        ids_to_keep = resorts.limit(allowed).pluck(:id)
        HomeResort.where(user_id: current_user.id)
                  .where.not(id: ids_to_keep)
                  .delete_all
      end
    end

    # STEP 6 — Write snapshot AFTER cleanup
    EntitlementSnapshotBuilder.write!(
      user: current_user,
      entitlements: normalized
    )

    # STEP 7 — Return normalized purchase state to client
    render json: { status: "ok", entitlements: normalized }
  end
end
