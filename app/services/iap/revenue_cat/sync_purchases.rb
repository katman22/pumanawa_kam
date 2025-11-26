# frozen_string_literal: true

module Iap
  module RevenueCat
    class SyncPurchases < ApplicationService
      attr_reader :user, :entitlements

      def initialize(user:, entitlements:)
        @user = user
        @entitlements = entitlements
      end

      def call
        ActiveRecord::Base.transaction do
          save_store_subscriptions!
          deactivate_stale_subscriptions!
        end

        enforce_home_resorts_for_current_tier!
      end

      private

      def enforce_home_resorts_for_current_tier!
        eff = Entitlements::Resolver.call(user: user)
        tier = eff.value[:tier] || "free"
        active = eff.value[:active]

        # --- DOWNGRADE expired or free user
        return unless tier == "free" && !active

        subs = HomeResort.for_user(user).subscribed
        return unless subs.exists?

        Rails.logger.info("[IAP Sync] Removing subscribed homes for free user=#{user.id}")
        subs.delete_all
      end

      def save_store_subscriptions!
        entitlements.each do |_entitlement_id, attrs|
          product_id = attrs["productIdentifier"]
          is_active = attrs["isActive"]
          will_renew = attrs["willRenew"]
          expiration = attrs["expirationDate"]
          purchase_date = attrs["latestPurchaseDate"]

          sub = Subscription.find_or_initialize_by(user: user, product_id: product_id)
          # Cancelled subscription (still active, but will not renew)
          if is_active && !will_renew
            sub.purchased_at = purchase_date
            sub.expires_at = expiration
            sub.will_renew = false
            sub.platform = map_platform(attrs)
            sub.source = "revenue_cat"
            sub.save!
            next
          end

          # Active and still renewing → update or create
          if is_active && will_renew
            sub.purchased_at = purchase_date
            sub.expires_at = expiration
            sub.will_renew = true
            sub.platform = map_platform(attrs)
            sub.source = "revenue_cat"
            sub.save!
            next
          end

          # Now inactive → mark as expired
          unless is_active
            sub.expires_at = expiration
            sub.will_renew = false
            sub.platform = map_platform(attrs)
            sub.source = "revenue_cat"
            sub.save!
            next
          end
        end
      end

      def deactivate_stale_subscriptions!
        not_active_products = entitlements.values.select { |e| !e["isActive"] }.map { |e| e["productIdentifier"] }
        user.subscriptions.active_ish
            .where(product_id: not_active_products)
            .update_all(status: "inactive", updated_at: Time.current)
      end

      def map_platform(attrs)
        which_store = (attrs["store"] || "").downcase
        return "ios" if %w[app_store mac_app_store].include?(which_store)
        return "android" if which_store == "play_store"
        "unknown"
      end
    end
  end
end
