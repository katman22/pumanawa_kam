# frozen_string_literal: true

require_relative "../discussion_base"

module Convert
  module Weather
    module Noaa
      class Discussion < DiscussionBase
        def self.call(raw_data)
          return nil if raw_data.blank?

          standard_format(
            synopsis: raw_data[:synopsis],
            short_term: raw_data[:short_term],
            long_range: raw_data[:long_range],
            fire_weather: raw_data[:fire_weather],
            aviation: raw_data[:aviation],
            watches_warnings: raw_data[:watches_warnings]
          )
        end
      end
    end
  end
end
