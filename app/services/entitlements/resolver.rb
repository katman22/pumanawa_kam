# frozen_string_literal: true

module Entitlements
  class Resolver < ApplicationService
    TIERS = { "free" => 0, "standard" => 1, "pro" => 2, "premium" => 3 }.freeze

    def initialize(user:)
      @user = user
    end

    def call
      snapshot = latest_snapshot
      override = active_override

      if snapshot.nil?
        return successful(default_payload)
      end

      merged = merge_snapshot_with_override(snapshot, override)
      successful(merged)
    end

    private

    def latest_snapshot
      EntitlementSnapshot.where(user_id: @user.id)
                         .order(created_at: :desc)
                         .first
    end

    def active_override
      EntitlementOverride.where(user_id: @user.id)
                         .where("starts_at <= ?", Time.current)
                         .where("ends_at IS NULL OR ends_at > ?", Time.current)
                         .order("ends_at NULLS LAST, starts_at DESC")
                         .first
    end

    def default_payload
      {
        version: 2,
        active: false,
        tier: "free",
        valid_until: nil,
        features: [],
        source_of_truth: "store",
        sources: {
          store:    { tier: "free", expires: nil, products: [], platforms: [] },
          override: { tier: "free", ends_at: nil, id: nil, reason: nil }
        }
      }
    end

    def merge_snapshot_with_override(snapshot, override)
      snap = {
        version: snapshot.version,
        active: snapshot.active,
        tier: snapshot.tier,
        valid_until: snapshot.valid_until,
        features: snapshot.features,
        sources: snapshot.source.deep_symbolize_keys
      }

      return snap unless override

      override_tier   = override.entitlement
      override_active = TIERS[override_tier] > TIERS[snap[:tier]]
      source_of_truth = override_active ? "override" : "store"

      if override_active
        {
          version: snap[:version],
          active: true,
          tier: override_tier,
          valid_until: override.ends_at,
          features: snap[:features], # or override-specific features later
          source_of_truth: "override",
          sources: {
            store: snap[:sources][:store],
            override: {
              tier: override.entitlement,
              ends_at: override.ends_at,
              id: override.id,
              reason: override.reason
            }
          }
        }
      else
        snap.merge(
          source_of_truth: "store",
          sources: snap[:sources].merge(
            override: {
              tier: override.entitlement,
              ends_at: override.ends_at,
              id: override.id,
              reason: override.reason
            }
          )
        )
      end
    end
  end
end
