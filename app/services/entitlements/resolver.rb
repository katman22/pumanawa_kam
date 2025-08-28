# frozen_string_literal: true

module Entitlements
  class Resolver < ApplicationService
    def initialize(user:)
      @user = user
    end

    def call
      subs = Subscription.current_for(@user)
      product_ids = subs.pluck(:product_id)
      flags = ProductCatalog.flags_for(product_ids)

      payload = {
        version: 1,
        active: flags.any?,
        tier: flags.any? ? "premium" : "free",
        expires_at: subs.map(&:expires_at).compact.max,
        platforms: subs.pluck(:platform).uniq,
        features: flags.sort
      }

      EntitlementSnapshot.create!(
        user: @user,
        version: payload[:version],
        active: payload[:active],
        tier: payload[:tier],
        valid_until: payload[:expires_at],
        features: payload[:features],
        source: { reason: "resolve" }
      )

      successful(payload)
    end
  end
end
