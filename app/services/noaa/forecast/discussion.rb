# frozen_string_literal: true

module Noaa
  module Forecast
    class Discussion < Base
      WEATHER_PRODUCTS = ->(office) { "https://api.weather.gov/products/types/AFD/locations/#{office}" }

      def initialize(latitude, longitude)
        @latitude = latitude
        @longitude = longitude
      end

      def call
        response = noaa_response
        return failed("Unable to retrieve forecast for #{latitude}, #{longitude}") if response.nil?

        index_response = product_index(response)
        return failed("Unable to retrieve detailed forecast location for: #{latitude}, #{longitude}") if index_response.body.nil? || index_response.body.empty?

        current_product_response = current_product(index_response)
        return failed("Could not retrieve current detailed forecast for: #{latitude}, #{longitude}") if current_product_response.body.nil? || current_product_response.body.empty?

        discussion_response = JSON.parse(current_product_response.body, symbolize_names: true)
        data = parse_product_text(discussion_response[:productText])
        converted_data = Convert::Weather::Noaa::Discussion.(data)

        successful(converted_data)
      end

      def current_product(index_response)
        parsed_response = JSON.parse(index_response.body, symbolize_names: true)
        product_url = parsed_response[:@graph].first[:@id]
        HTTParty.get(product_url, headers: noaa_agent_header)
      end

      def product_index(response)
        office = response["properties"]["cwa"]
        index_url = WEATHER_PRODUCTS.call(office)
        HTTParty.get(index_url, headers: noaa_agent_header)
      end

      def noaa_agent_header
        { "User-Agent" => "aura_weather (#{ENV['APPLICATION_EMAIL']})" }
      end

      def parse_product_text(text)
        sections = {
          synopsis: extract_section(text, "SYNOPSIS"),
          key_messages: extract_section(text, "KEY MESSAGES"),
          discussion: extract_section(text, "DISCUSSION"),
          short_term: extract_section(text, "SHORT TERM"),
          long_term: extract_section(text, "LONG TERM"),
          fire_weather: extract_section(text, "FIRE WEATHER"),
          aviation: extract_section(text, "AVIATION"),
          watches_warnings: extract_section(text, "WATCHES/WARNINGS/ADVISORIES", office_prefix: true)
        }
        short_term, long_range = split_short_and_long(sections)
        {
          synopsis: sections[:synopsis] || sections[:key_messages] || "No summary available",
          short_term: short_term || "No forecast available",
          long_range: long_range || "No extended forecast available",
          aviation: sections[:aviation] || "No aviation forecast available",
          fire_weather: sections[:fire_weather] || "No fire forecast available",
          watches_warnings: sections[:watches_warnings] || "None"
        }
      end

      def extract_section(text, name, office_prefix: false)
        prefix = office_prefix ? "(?:[A-Z]{3}[ \\t]+)?" : ""
        # Stop at a delimiter, the next section heading, or the end of the product.
        pattern = /^\.#{prefix}#{Regexp.escape(name)}(?:[ \t]*,[^\n]*)?\.{3}[ \t]*\n(.*?)(?=^[ \t]*&&[ \t]*$|^\.[A-Z][^\n]*\.{3}[ \t]*$|\z)/m
        text.to_s.gsub("\r\n", "\n").match(pattern)&.[](1)&.strip.presence
      end

      def split_short_and_long(sections)
        paragraphs = sections[:discussion].to_s.split(/\n[ \t]*\n+/).map(&:strip).reject(&:empty?)
        summary = sections[:key_messages] || sections[:synopsis]
        short_term = sections[:short_term] || summary || paragraphs.first
        long_range = sections[:long_term]
        unless long_range || sections[:short_term]
          long_range = summary ? sections[:discussion] : paragraphs.drop(1).join("\n\n").presence
        end
        [ short_term, long_range ]
      end
    end
  end
end
