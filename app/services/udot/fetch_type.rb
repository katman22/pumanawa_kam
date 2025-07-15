# frozen_string_literal: true

module Udot
  class FetchType < ApplicationService
    attr_reader :type, :filter

    UDOT_KEY = ENV.fetch("UDOT_KEY")
    UDOT_API = ENV.fetch("UDOT_API")

    def initialize(type:, filter: {})
      @type = type
      @filter = filter
    end

    def call
      response = fetch_and_cache_udot
      return failed(response.message) unless response.success?

      data = response.parsed_response || []
      data = apply_filter(data)
      successful(data)
    end

    private

    def fetch_and_cache_udot
      url = "#{UDOT_API}/#{type}"
      Rails.cache.fetch("udot_#{type}", expires_in: 10.minutes.to_i) do
        HTTParty.get(url, query: { key: UDOT_KEY })
      end
    end

    def apply_filter(data)
      return data if filter.blank?
      data.select do |item|
        filter.all? { |k, v| item[k.to_s]&.include?(v) }
      end
    end
  end
end
