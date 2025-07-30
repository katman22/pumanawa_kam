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
        response = parse_response(noaa_response)
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
          synopsis: extract_between(text, ".SYNOPSIS...", "&&") || extract_between(text, ".KEY MESSAGES...", "&&"),
          discussion: extract_between(text, ".SHORT TERM", ".AVIATION") || extract_between(text, ".DISCUSSION...", "&&"),
          fire_weather: extract_between(text, ".FIRE WEATHER", "&&"),
          aviation: extract_between(text, ".AVIATION", "&&"),
          watches_warnings: extract_between(text, "WATCHES/WARNINGS/ADVISORIES...", "&&") || "None"
        }
        @short_term, @long_range = split_short_and_long(sections[:discussion])
        {
          synopsis: sections[:synopsis]&.strip || "No summary available",
          short_term: @short_term&.strip || "No forecast available",
          long_range: @long_range&.strip || "No extended forecast available",
          aviation: sections[:aviation]&.strip || "No aviation forecast available",
          fire_weather: sections[:fire_weather]&.strip || "No fire forecast available",
          watches_warnings: sections[:watches_warnings]&.strip || "No watches or warning available"
        }
      end

      def extract_between(text, start_marker, end_marker)
        pattern = /#{Regexp.escape(start_marker)}(.*?)#{Regexp.escape(end_marker)}/m
        match = text.match(pattern)
        match ? match[1] : nil
      end

      def split_short_and_long(discussion)
        return [ nil, nil ] unless discussion

        start_index = discussion.index(/LONG TERM/i) ||
          discussion.index(/(Friday|This weekend|Extended Forecast|Wednesday and beyond)/i)
        return [ discussion, nil ] unless start_index

        short_term = discussion[0...start_index].strip
        long_range = discussion[start_index...discussion.length].strip

        [ short_term, long_range ]
      end
    end
  end
end
