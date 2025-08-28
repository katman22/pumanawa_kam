# frozen_string_literal: true

module Iap
  # Normalized attrs structure expected:
  # {
  #   platform: "ios"|"android",
  #   product_id: "ct_premium_month",
  #   transaction_id: "abc",
  #   original_transaction_id: "orig123",
  #   status: "active"|"in_grace"|"on_hold"|"canceled"|"expired",
  #   started_at: Time, expires_at: Time, revoked_at: Time|nil,
  #   auto_renew: true/false,
  #   raw_status: {...},
  #   receipt_token: "token", raw_receipt: {...}
  # }
  class UpsertSubscription < ApplicationService
    def initialize(user:, attrs:)
      @user = user
      @attrs = attrs
    end

    def call
      ActiveRecord::Base.transaction do
        sub = Subscription.find_or_initialize_by(
          user_id: @user.id,
          platform: @attrs[:platform],
          product_id: @attrs[:product_id],
          original_transaction_id: @attrs[:original_transaction_id]
        )

        sub.assign_attributes(
          status: @attrs[:status],
          started_at: @attrs[:started_at],
          expires_at: @attrs[:expires_at],
          revoked_at: @attrs[:revoked_at],
          auto_renew: @attrs[:auto_renew],
          latest_transaction_id: @attrs[:transaction_id],
          raw_status: @attrs[:raw_status] || {}
        )
        sub.save!

        if @attrs[:receipt_token].present?
          Receipt.create!(
            user_id: @user.id,
            platform: @attrs[:platform],
            product_id: @attrs[:product_id],
            transaction_id: @attrs[:transaction_id],
            token: @attrs[:receipt_token],
            raw_json: @attrs[:raw_receipt] || {}
          )
        end

        successful(sub)
      end
    end
  end
end
