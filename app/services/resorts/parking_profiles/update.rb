# frozen_string_literal: true

module Resorts
  module ParkingProfiles
    class Update < ApplicationService
      JSON_ARRAY_FIELDS = %i[links rules faqs sources].freeze
      JSON_OBJECT_FIELDS = %i[operations highway_parking accessibility media].freeze

      def initialize(resort_id:, params:)
        @resort_id = resort_id
        @resort = Resort.find(resort_id)
        @profile = ParkingProfile.find_by!(resort: @resort, season: params[:season])
        @params = params
      end

      # Parse date times
      # Parse boolean (checkbox sends "0"/"1" or "true"/"false")
      # Parse JSON fields
      def call
        raw = @params
        raw[:effective_from] = parse_time(raw[:effective_from])
        raw[:effective_to] = parse_time(raw[:effective_to])
        raw[:overnight] = ActiveModel::Type::Boolean.new.cast(raw[:overnight])
        JSON_ARRAY_FIELDS.each { |k| raw[k] = parse_json_array(raw[k], k) }
        JSON_OBJECT_FIELDS.each { |k| raw[k] = parse_json_object(raw[k], k) }

        @profile.with_lock do
          @profile.update!(raw.merge(
            version: @profile.version + 1,
            updated_by: "admin-lite:#{ENV.fetch("ADMIN_USER", "unknown")}"
          ))
        end
        successful(@profile)
      rescue JSON::ParserError => e
        failed("Error parsing data: #{e.message}")
      rescue
        failed("Parking profile could not be created")
      end

      private

      def parse_time(s)
        s.present? ? Time.zone.parse(s) : nil
      end

      def parse_json_array(s, key)
        return [] if s.blank?
        val = JSON.parse(s)
        raise JSON::ParserError, "#{key} must be an array" unless val.is_a?(Array)
        val
      end

      def parse_json_object(s, key)
        return {} if s.blank?
        val = JSON.parse(s)
        raise JSON::ParserError, "#{key} must be an object" unless val.is_a?(Hash)
        val
      end
    end
  end
end
