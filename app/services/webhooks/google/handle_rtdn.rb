# frozen_string_literal: true

module Webhooks
  module Google
    class HandleRtdn < ApplicationService
      def initialize(raw:)
        @raw = raw # string or parsed JSON from Pub/Sub push
      end

      def call
        body = @raw.is_a?(String) ? JSON.parse(@raw) : @raw
        event_id = body["messageId"] || SecureRandom.uuid
        event_type = "RTDN"

        event = WebhookEvent.create!(
          provider: "google",
          event_type: event_type,
          idempotency_key: event_id,
          raw: body
        )

        # TODO: fetch subscriptions v2.get with {productId, purchaseToken}, upsert
        event.update!(status: "ok", processed_at: Time.current)
        successful(event)
      rescue => e
        event&.update!(status: "error", error: e.message)
        failed(e.message)
      end
    end
  end
end
