# frozen_string_literal: true

module Iap
  module RevenueCat
    class SyncPurchases < ApplicationService
      attr_reader :user, :entitlements

      # entitlements is a hash:
      # { "pro" => { "productIdentifier" => "...", "isActive" => true, ... }, ... }
      def initialize(user:, entitlements:)
        @user         = user
        @entitlements = entitlements || {}
      end

      # MAIN ENTRY
      def call
        ActiveRecord::Base.transaction do
          save_store_subscriptions!
          deactivate_stale_subscriptions!
        end

        # Instead of calling resolver (which reads old snapshot),
        # we build normalized entitlements directly from Subscription rows.
        successful(compute_current_entitlements!)
      end

      private

      #
      # STEP 1: Write/update Subscription rows from RevenueCat data
      #
      def save_store_subscriptions!
        entitlements.each do |_id, attrs|
          product_id   = attrs["productIdentifier"]
          is_active    = attrs["isActive"]
          will_renew   = attrs["willRenew"]
          expires_at   = parse_time(attrs["expirationDate"])
          purchased_at = parse_time(attrs["latestPurchaseDate"])
          platform     = map_platform(attrs)

          sub = Subscription.find_or_initialize_by(user: user, product_id: product_id)
          sub.purchased_at = purchased_at
          sub.expires_at   = expires_at
          sub.will_renew   = !!will_renew
          sub.platform     = platform
          sub.source       = "revenue_cat"

          # Status based purely on RevenueCat's isActive
          sub.status = is_active ? "active" : "inactive"

          sub.save!
        end
      end

      #
      # STEP 2: Mark stale subscriptions inactive (NOT present in RevenueCat response)
      #
      def deactivate_stale_subscriptions!
        active_ids = entitlements.values.select { |e| e["isActive"] }.map { |e| e["productIdentifier"] }

        # Any subscription that USED to be active, but is not in the incoming active_ids, becomes inactive
        user.subscriptions.active_ish
            .where.not(product_id: active_ids)
            .update_all(status: "inactive", updated_at: Time.current)
      end

      #
      # STEP 3: Build *normalized entitlement hash* directly from Subscription rows
      #
      def compute_current_entitlements!
        subs = user.subscriptions

        active_sub = subs.where(status: "active")
                         .where("expires_at IS NULL OR expires_at > ?", Time.current)
                         .order(expires_at: :desc)
                         .first

        # Read manual override (if present)
        override = EntitlementOverride.where(user_id: user.id)
                                      .where("starts_at <= ?", Time.current)
                                      .where("ends_at IS NULL OR ends_at > ?", Time.current)
                                      .order("ends_at NULLS LAST, starts_at DESC")
                                      .first

        #
        # CASE 1 — No store subscription
        #
        if active_sub.nil?
          if override
            # override beats free
            return {
              version: 2,
              active: true,
              tier: override.entitlement,
              valid_until: override.ends_at,
              features: features_for_tier(override.entitlement),
              source_of_truth: "override",
              sources: {
                store:    { tier: "free", expires: nil, products: [], platforms: [] },
                override: {
                  tier:    override.entitlement,
                  ends_at: override.ends_at,
                  id:      override.id,
                  reason:  override.reason
                }
              }
            }
          else
            # regular free user
            return {
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
        end

        #
        # CASE 2 — User has store subscription (standard/pro/premium)
        #
        store_tier = derive_tier_from_product(active_sub.product_id)

        # If override exists AND it is higher
        if override && TIERS[override.entitlement] > TIERS[store_tier]
          return {
            version: 2,
            active: true,
            tier: override.entitlement,
            valid_until: override.ends_at || active_sub.expires_at,
            features: features_for_tier(override.entitlement),
            source_of_truth: "override",
            sources: {
              store: {
                tier: store_tier,
                expires: active_sub.expires_at,
                products: subs.map(&:product_id),
                platforms: subs.map(&:platform)
              },
              override: {
                tier: override.entitlement,
                ends_at: override.ends_at,
                id: override.id,
                reason: override.reason
              }
            }
          }
        end

        #
        # OTHERWISE store subscription wins
        #
        {
          version: 2,
          active: true,
          tier: store_tier,
          valid_until: active_sub.expires_at,
          features: features_for_tier(store_tier),
          source_of_truth: "store",
          sources: {
            store: {
              tier: store_tier,
              expires: active_sub.expires_at,
              products: subs.map(&:product_id),
              platforms: subs.map(&:platform)
            },
            override: {
              tier: override ? override.entitlement : store_tier,
              ends_at: override&.ends_at,
              id: override&.id,
              reason: override&.reason
            }
          }
        }
      end

      #
      # Helpers
      #
      def parse_time(t)
        return nil if t.blank?
        Time.parse(t) rescue nil
      end

      def map_platform(attrs)
        which_store = (attrs["store"] || "").downcase
        return "ios" if %w[app_store mac_app_store].include?(which_store)
        return "android" if which_store == "play_store"
        "unknown"
      end

      # map product id → tier
      def derive_tier_from_product(pid)
        return "standard" if pid.include?("standard")
        return "pro"      if pid.include?("pro")
        return "premium"  if pid.include?("premium")
        "free"
      end

      def features_for_tier(tier)
        case tier
        when "standard" then %w[home_resorts:2 cameras:unlimited]
        when "pro"      then %w[home_resorts:4 cameras:unlimited traffic:premium]
        when "premium"  then %w[home_resorts:6 cameras:unlimited everything]
        else []
        end
      end
    end
  end
end
