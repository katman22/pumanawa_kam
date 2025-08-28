# frozen_string_literal: true
module Webhooks
  module Apple
    class HandleNotification < ApplicationService
      def initialize(jwt:)
        @jwt = jwt
      end

      def call
        # TODO: verify signature & parse ASN v2 JWT
        parsed = { event_id: SecureRandom.uuid, event_type: "DID_RENEW", data: {} }

        event = WebhookEvent.create!(
          provider: "apple",
          event_type: parsed[:event_type],
          idempotency_key: parsed[:event_id],
          raw: { jwt: @jwt }
        )

        # TODO: map parsed data to normalized attrs and upsert
        # Iap::UpsertSubscription.call!(user: user, attrs: normalized)

        event.update!(status: "ok", processed_at: Time.current)
        successful(event)
      rescue => e
        event&.update!(status: "error", error: e.message)
        failed(e.message)
      end
    end
  end
end
