# frozen_string_literal: true
module Iap
  module Apple
    class Verify < ApplicationService
      def initialize(payload:)
        @payload = payload # e.g. { "signedTransactionInfo": "...", ... } or base64 receipt
      end

      def call
        # TODO: Call App Store Server API with your issuer/key to verify transaction
        # For now, assume payload already has normalized fields during sandbox.
        normalized = normalize_stub(@payload)
        successful(normalized)
      end

      private

      def normalize_stub(p)
        now = Time.current
        {
          platform: "ios",
          product_id: p[:productId] || p["productId"],
          transaction_id: p[:transactionId] || p["transactionId"],
          original_transaction_id: p[:originalTransactionId] || p["originalTransactionId"] || p[:transactionId],
          status: "active",
          started_at: now - 5.minutes,
          expires_at: now + 30.days,
          revoked_at: nil,
          auto_renew: true,
          raw_status: p,
          receipt_token: p[:receipt] || p["receipt"] || p[:signedTransactionInfo],
          raw_receipt: p
        }
      end
    end
  end
end
