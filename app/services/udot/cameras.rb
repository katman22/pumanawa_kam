# frozen_string_literal: true

module Udot
  class Cameras < ApplicationService
    attr_reader :resort

    UDOT_KEY = ENV.fetch("UDOT_KEY")
    UDOT_API = ENV.fetch("UDOT_API")
    UDOT_ERROR = "No UDOT data available currently."
    CAMERAS = "cameras"

    def initialize(resort:)
      @resort = resort
    end

    def call
      cameras = udot_cameras
      successful(cameras)
    end

    private


    def udot_cameras
      udot_response = Udot::FetchType.new(type: CAMERAS, filter: resort.camera).call
      return UDOT_ERROR if udot_response.failure?
      udot_response.value.map
    end
  end
end
