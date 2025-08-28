# frozen_string_literal: true

module Iap
  module Google
    class Verify < ApplicationService
      def initialize(payload:)
        @payload = payload # e.g. { "productId": "...", "purchaseToken": "..." }
      end

      def call
        # TODO: Use Google Play Developer API (subscriptionsv2.get) with service account
        normalized = normalize_stub(@payload)
        successful(normalized)
      end

      private

      def normalize_stub(p)
        now = Time.current
        {
          platform: "android",
          product_id: p[:productId] || p["productId"],
          transaction_id: p[:orderId] || p["orderId"] || p[:purchaseToken],
          original_transaction_id: p[:linkedPurchaseToken] || p["linkedPurchaseToken"] || p[:purchaseToken],
          status: "active",
          started_at: now - 5.minutes,
          expires_at: now + 30.days,
          revoked_at: nil,
          auto_renew: true,
          raw_status: p,
          receipt_token: p[:purchaseToken] || p["purchaseToken"],
          raw_receipt: p
        }
      end
    end
  end
end
