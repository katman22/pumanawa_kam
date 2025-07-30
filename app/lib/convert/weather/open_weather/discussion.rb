# frozen_string_literal: true

require_relative "../discussion_base"

module Convert
  module Weather
    module OpenWeather
      class Discussion < DiscussionBase
        def self.call(raw_data)
          return nil if raw_data.blank?

          parsed = raw_data.is_a?(String) ? JSON.parse(raw_data, symbolize_names: true) : raw_data

          alerts_summary = format_alerts(parsed[:alerts] || [])

          standard_format(
            synopsis: "No synopsis available",  # OpenWeather doesn't currently provide this
            short_term: parsed[:short_term],
            long_range: parsed[:long_term],
            fire_weather: "",  # Not explicitly provided
            aviation: "",      # Not available
            watches_warnings: alerts_summary
          )
        end

        def self.format_alerts(alerts)
          return "None." if alerts.empty?

          alerts.map do |alert|
            [
              alert[:event],
              alert[:headline],
              alert[:description],
              alert[:instruction]
            ].compact.join("\n\n")
          end.join("\n\n---\n\n")
        end
      end
    end
  end
end
