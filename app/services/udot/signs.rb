# frozen_string_literal: true

module Udot
  class Signs < ApplicationService
    attr_reader :resort

    UDOT_KEY = ENV.fetch("UDOT_KEY")
    UDOT_API = ENV.fetch("UDOT_API")
    UDOT_ERROR = "No UDOT data available currently."
    SIGNS = "messagesigns"
    EXCLUSIONS = "EncodedPolyline"

    def initialize(resort:)
      @resort = resort
    end

    def call
      signs = udot_signs
      successful(signs)
    end

    private

    def udot_signs
      udot_response = Udot::FetchType.new(type: SIGNS, filter: filter(resort, "camera")).call
      return UDOT_ERROR if udot_response.failure?
      udot_response.value.map { |entry| entry.except(EXCLUSIONS) }
    end

    def filter(resort, kind)
      filter = resort.resort_filters.select { |filter| filter.kind == kind }.first
      filter.parsed_data
    end

  end
end
