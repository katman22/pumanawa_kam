# frozen_string_literal: true

module Resorts
  module ParkingProfiles
    class Create < ApplicationService
      attr_reader :resort, :season

      def initialize(resort_id:, season:, actor:)
        @season = season
        @actor = actor
        @resort = Resort.find(resort_id)
      end

      def call
        ActiveRecord::Base.transaction do
          from, to = ParkingSeason.default_window(season)
          @profile = ParkingProfile.find_or_create_by!(resort: resort, season: season) do |pp|
            pp.effective_from = from
            pp.effective_to = to
            pp.version = 1
            pp.updated_by = "admin:#{@actor.id}:#{@actor.username}".truncate(120)
          end
        end
        successful(@profile)
      rescue ActiveRecord::RecordInvalid
        failed("Parking profile could not be created")
      end
    end
  end
end
