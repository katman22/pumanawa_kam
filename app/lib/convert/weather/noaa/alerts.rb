# frozen_string_literal: true

require_relative "../alert_base"

module Convert
  module Weather
    module Noaa
      class Alerts < AlertBase
        def self.call(raw_data)
          return [] if raw_data.blank?

          raw_data.map do |alert|
            props = alert["properties"] || {}

            standard_format(
              event: props["event"],
              headline: props["headline"],
              description: props["description"],
              instruction: props["instruction"],
              category: props["category"],
              status: props["status"],
              severity: props["severity"],
              certainty: props["certainty"],
              urgency: props["urgency"],
              onset: props["onset"],
              effective: props["effective"],
              expires: props["expires"],
              ends: props["ends"],
              sender_name: props["senderName"],
              sender: props["senderName"],
              message_type: props["messageType"],
              response: props["response"]
            )
          end
        end
      end
    end
  end
end
