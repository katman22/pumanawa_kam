# frozen_string_literal: true

# Parser tests need Rails autoloading, but no database or fixtures.
ENV["RAILS_ENV"] ||= "test"
require_relative "../../../../config/environment"
require "minitest/autorun"

module Noaa
  module Forecast
    class DiscussionTest < Minitest::Test
      def setup
        @parser = Discussion.new(40.5986, -111.5845)
      end

      def test_legacy_and_current_headings_with_both_line_endings
        [ "", ", Issued 1027 PM MDT Fri Oct 9 2026", ", arbitrary metadata without a timestamp" ].each do |metadata|
          [ "\n", "\r\n" ].each do |newline|
            text = product(
              "KEY MESSAGES#{metadata}" => "Summary first line.\nWrapped summary line.",
              "DISCUSSION#{metadata}" => "Friday brings rain.\nStill the same paragraph.\n\nThis weekend stays wet.",
              "AVIATION#{metadata}" => "Aviation body.",
              "FIRE WEATHER#{metadata}" => "Fire body.",
              "SLC WATCHES/WARNINGS/ADVISORIES#{metadata}" => "UT...None."
            ).gsub("\n", newline)

            result = @parser.parse_product_text(text)
            assert_equal "Summary first line.\nWrapped summary line.", result[:short_term]
            assert_equal result[:short_term], result[:synopsis]
            assert_equal "Friday brings rain.\nStill the same paragraph.\n\nThis weekend stays wet.", result[:long_range]
            assert_equal "Aviation body.", result[:aviation]
            assert_equal "Fire body.", result[:fire_weather]
            assert_equal "UT...None.", result[:watches_warnings]
          end
        end
      end

      def test_explicit_short_and_long_term_take_precedence
        [ "", ", unrelated metadata" ].each do |metadata|
          result = @parser.parse_product_text(product(
            "KEY MESSAGES" => "Key summary.",
            "SYNOPSIS" => "Synopsis body.",
            "DISCUSSION" => "General discussion.",
            "SHORT TERM#{metadata}" => "Explicit short body.",
            "LONG TERM#{metadata}" => "Explicit long body."
          ))
          assert_equal "Explicit short body.", result[:short_term]
          assert_equal "Explicit long body.", result[:long_range]
          assert_equal "Synopsis body.", result[:synopsis]
        end
      end

      def test_key_messages_preferred_over_synopsis_for_short_term
        result = @parser.parse_product_text(product(
          "SYNOPSIS" => "Synopsis body.",
          "KEY MESSAGES" => "Key summary.",
          "DISCUSSION" => "First paragraph.\n\nSecond paragraph."
        ))
        assert_equal "Key summary.", result[:short_term]
        assert_equal "First paragraph.\n\nSecond paragraph.", result[:long_range]
        assert_equal "Synopsis body.", result[:synopsis]
      end

      def test_synopsis_fallback_with_tolerant_heading
        result = @parser.parse_product_text(product(
          "SYNOPSIS, metadata" => "Synopsis body.",
          "DISCUSSION" => "Full discussion."
        ))
        assert_equal "Synopsis body.", result[:short_term]
        assert_equal "Full discussion.", result[:long_range]
      end

      def test_discussion_paragraph_fallback_preserves_wrapped_lines
        [ "\n", "\r\n" ].each do |newline|
          text = product("DISCUSSION, metadata" => "\nFirst paragraph.\nWrapped line.\n \n\nSecond paragraph.\nWrapped again.\n\nThird paragraph.")
          result = @parser.parse_product_text(text.gsub("\n", newline))
          assert_equal "First paragraph.\nWrapped line.", result[:short_term]
          assert_equal "Second paragraph.\nWrapped again.\n\nThird paragraph.", result[:long_range]
        end
      end

      def test_weekday_words_do_not_split_a_paragraph
        body = "Friday brings rain. This weekend stays wet.\nWednesday and beyond remains unsettled."
        result = @parser.parse_product_text(product("DISCUSSION" => body))
        assert_equal body, result[:short_term]
        assert_equal "No extended forecast available", result[:long_range]
      end

      def test_explicit_long_term_overrides_discussion_remainder
        result = @parser.parse_product_text(product(
          "DISCUSSION" => "First paragraph.\n\nSecond paragraph.",
          "LONG TERM" => "Explicit extended body."
        ))
        assert_equal "First paragraph.", result[:short_term]
        assert_equal "Explicit extended body.", result[:long_range]
      end

      def test_explicit_short_term_without_long_term_keeps_extended_fallback
        result = @parser.parse_product_text(product(
          "SHORT TERM" => "Short body.",
          "KEY MESSAGES" => "Summary.",
          "DISCUSSION" => "Discussion body."
        ))
        assert_equal "Short body.", result[:short_term]
        assert_equal "No extended forecast available", result[:long_range]
      end

      def test_prefixed_and_unprefixed_warnings
        [ "", "SLC ", "BOU " ].each do |prefix|
          result = @parser.parse_product_text(product("#{prefix}WATCHES/WARNINGS/ADVISORIES" => "UT...Warning."))
          assert_equal "UT...Warning.", result[:watches_warnings]
        end
      end

      def test_missing_and_empty_section_fallbacks
        expected = {
          synopsis: "No summary available",
          short_term: "No forecast available",
          long_range: "No extended forecast available",
          aviation: "No aviation forecast available",
          fire_weather: "No fire forecast available",
          watches_warnings: "None"
        }
        assert_equal expected, @parser.parse_product_text("Product header only.")
        assert_equal expected, @parser.parse_product_text(product("KEY MESSAGES" => " \n", "DISCUSSION" => "\n"))
      end

      def test_headings_require_line_start_and_three_dots
        text = "Prose .KEY MESSAGES...\nNot a section.\n&&\n.DISCUSSION..\nNot a valid heading.\n&&\n"
        result = @parser.parse_product_text(text)
        assert_equal "No summary available", result[:synopsis]
        assert_equal "No forecast available", result[:short_term]
      end

      def test_next_heading_bounds_body_without_delimiter
        text = ".SHORT TERM, metadata...\nShort body.\n.LONG TERM, other metadata...\nLong body.\n.AVIATION...\nAir body."
        result = @parser.parse_product_text(text)
        assert_equal "Short body.", result[:short_term]
        assert_equal "Long body.", result[:long_range]
        assert_equal "Air body.", result[:aviation]
      end

      private

      def product(sections)
        sections.map { |name, body| ".#{name}...\n#{body}\n&&\n" }.join
      end
    end
  end
end
