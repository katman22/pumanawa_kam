# frozen_string_literal: true

module Udot
  class FeaturedCameras < ApplicationService
    attr_reader :resort

    UDOT_KEY = ENV.fetch("UDOT_KEY")
    UDOT_API = ENV.fetch("UDOT_API")
    UDOT_ERROR = "No UDOT data available currently."
    CAMERAS = "cameras"

    def initialize(resort:)
      @resort = resort
    end

    def call
      cameras = featured_cameras
      successful(cameras)
    end

    private

    def featured_cameras
      cameras = @resort.cameras.where(featured: true, kind: "traffic").map { |resort| resort.data }
      return cameras.map unless cameras.empty?

      udot_response = Udot::FetchType.new(type: CAMERAS, filter: filter(resort, "camera")).call
      enabled = udot_response.value.select { |camera| camera["Views"].first["Status"] != "Disabled" }
      return UDOT_ERROR if udot_response.failure?
      (enabled[0..1]).map
    end

    def filter(resort, kind)
      filter = resort.resort_filters.select { |filter| filter.kind == kind }.first
      filter.parsed_data
    end
  end
end
