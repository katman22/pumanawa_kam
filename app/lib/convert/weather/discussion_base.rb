# frozen_string_literal: true

module Convert
  module Weather
    class DiscussionBase
      def self.call(_raw_data)
        raise NotImplementedError, "Subclasses must implement .call"
      end

      def self.standard_format(
        synopsis:,
        short_term:,
        long_range:,
        fire_weather:,
        aviation:,
        watches_warnings:
      )
        {
          synopsis: synopsis,
          short_term: short_term,
          long_range: long_range,
          fire_weather: fire_weather,
          aviation: aviation,
          watches_warnings: watches_warnings
        }
      end
    end
  end
end
