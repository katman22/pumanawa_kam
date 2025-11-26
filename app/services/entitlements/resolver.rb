# frozen_string_literal: true

require "digest"

module Entitlements
  class Resolver < ApplicationService
    TIERS = { "free" => 0, "standard" => 1, "pro" => 2, "premium" => 3 }.freeze

    def initialize(user:)
      @user = user
    end

    def call
      store_subs = Subscription.current_for(@user)
      store_products = store_subs.pluck(:product_id)
      store_tier = tier_for_products(store_products)
      store_flags = flags_for_products(store_products)
      store_expires = store_subs.map(&:expires_at).compact.max
      store_platforms = store_subs.pluck(:platform).uniq

      override = active_override(@user)
      override_tier = override&.entitlement || "free"
      override_flags = feature_flags_for_override(override)
      override_until = override&.ends_at

      eff_tier = max_by_tier(store_tier, override_tier)
      eff_flags = normalize_feature_flags(store_flags + override_flags)
      eff_active = eff_tier != "free"
      eff_until =
        if TIERS[override_tier] > TIERS[store_tier]
          override_until
        else
          store_expires
        end

      payload = {
        version: 2,
        active: eff_active,
        tier: eff_tier,
        valid_until: eff_until&.iso8601,
        features: eff_flags,
        source_of_truth: TIERS[override_tier] > TIERS[store_tier] ? "override" : "store",
        sources: {
          store: {
            tier: store_tier,
            expires: store_expires&.iso8601,
            products: store_products,
            platforms: store_platforms
          },
          override: {
            tier: override_tier,
            ends_at: override_until&.iso8601,
            id: override&.id,
            reason: override&.reason
          }
        }
      }

      # ---------- Idempotent snapshot write ----------
      fp = fingerprint_for(payload)
      last_before = EntitlementSnapshot.where(user_id: @user.id)
                                       .order(id: :desc)
                                       .limit(1)
                                       .first

      if last_before&.fingerprint.present? && last_before.fingerprint == fp
        return successful(payload)
      end

      begin
        EntitlementSnapshot.transaction(requires_new: true) do
          EntitlementSnapshot.create!(
            user: @user,
            version: payload[:version],
            active: payload[:active],
            tier: payload[:tier],
            valid_until: payload[:valid_until],
            features: payload[:features],
            source: payload[:sources],
            fingerprint: fp
          )
        end
      rescue ActiveRecord::RecordNotUnique
        # Snapshot for this fingerprint already exists
      end

      successful(payload)
    end

    private

    def fingerprint_for(payload)
      canonical = {
        v: payload[:version],
        active: payload[:active] ? 1 : 0,
        tier: payload[:tier],
        until: payload[:valid_until]&.to_i,
        features: Array(payload[:features]).sort,
        src: {
          store: { tier: payload.dig(:sources, :store, :tier),
                   exp: payload.dig(:sources, :store, :expires)&.then { |t| Time.parse(t).to_i } },
          override: { tier: payload.dig(:sources, :override, :tier),
                      end: payload.dig(:sources, :override, :ends_at)&.then { |t| Time.parse(t).to_i } }
        }
      }
      Digest::SHA256.hexdigest(canonical.to_json)
    end

    def tier_for_products(product_ids)
      return "free" if product_ids.blank?

      tiers = product_ids.map { |pid| tier_for_product(pid) }.compact.uniq

      if tiers.many?
        Rails.logger.warn("[Entitlements] Mixed tier products for user=#{@user.id}: #{tiers.inspect}")
      end

      tiers.max_by { |t| TIERS[t] } || "free"
    end

    def tier_for_product(product_id)
      pc = ProductCatalog.find_by(external_id_ios: product_id, status: "active") ||
        ProductCatalog.find_by(external_id_android: product_id, status: "active")
      pc&.tier || "free"
    end

    def flags_for_products(product_ids)
      return [] if product_ids.blank?

      ProductCatalog.where(status: "active")
                    .where("external_id_ios IN (?) OR external_id_android IN (?)", product_ids, product_ids)
                    .pluck(:feature_flags)
                    .flatten
                    .uniq
    end

    def normalize_feature_flags(flags)
      homes = flags.grep(/\Ahomes:/).map { |f| f.split(":").last.to_i }.max
      changes = flags.grep(/\Achanges:/).map { |f| f.split(":").last.to_i }.max
      others = flags.reject { |f| f.start_with?("homes:") || f.start_with?("changes:") }

      out = []
      out << "homes:#{homes}" if homes
      out << "changes:#{changes}" if changes
      out.concat(others)
      out.uniq.sort
    end

    def active_override(user)
      EntitlementOverride.where(user_id: user.id)
                         .where("starts_at <= ?", Time.current)
                         .where("ends_at IS NULL OR ends_at > ?", Time.current)
                         .order("ends_at NULLS LAST, starts_at DESC")
                         .first
    end

    def feature_flags_for_override(_override)
      []
    end

    def max_by_tier(a, b)
      TIERS[a].to_i >= TIERS[b].to_i ? a : b
    end
  end
end
