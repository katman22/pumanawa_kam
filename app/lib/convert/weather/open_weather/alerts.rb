# frozen_string_literal: true

require_relative "../alert_base"

module Convert
  module Weather
    module OpenWeather
      class Alerts < AlertBase
        def self.call(raw_data)
          return [] if raw_data.blank?

          parsed = raw_data.is_a?(String) ? JSON.parse(raw_data) : raw_data
          alerts = parsed["alerts"] || []

          alerts.map do |alert|
            standard_format(
              event: alert["event"],
              headline: alert["event"], # OpenWeather does not provide a separate headline
              description: alert["description"],
              category: "",
              instruction: nil, # No field provided
              status: nil,      # Not included by OpenWeather
              severity: alert["severity"],   # Might be nil, OpenWeather optional
              certainty: nil,   # Not included
              urgency: nil,     # Not included
              onset: alert["start"] ? Time.at(alert["start"]).iso8601 : nil,
              effective: alert["start"] ? Time.at(alert["start"]).iso8601 : nil,
              expires: alert["end"] ? Time.at(alert["end"]).iso8601 : nil,
              ends: alert["end"] ? Time.at(alert["end"]).iso8601 : nil,
              sender_name: alert["sender_name"],
              sender: alert["sender_name"],
              message_type: nil,  # Not available
              response: nil       # Not available
            )
          end
        end
      end
    end
  end
end
