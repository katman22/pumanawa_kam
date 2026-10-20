# frozen_string_literal: true

module Noaa
  module Forecast
    class GridData < ApplicationService
      def initialize(mapping:, validators: {}, retained: nil)
        @mapping, @validators, @retained = mapping, validators, retained
      end

      def call
        url = @mapping["forecastGridData"]
        result = Noaa::Request.call(url: url, headers: @validators.compact)
        return result if result.failure?
        if result.value["status"] == 304
          return successful(result.value.merge("body" => @retained)) if @retained

          result = Noaa::Request.call(url: url)
          return result if result.failure?
          return failed(code: "unusable_not_modified") if result.value["status"] == 304
        end
        properties = result.value.dig("body", "properties")
        valid = properties.is_a?(Hash) && properties["gridId"] == @mapping["gridId"] &&
          properties["gridX"] == @mapping["gridX"] && properties["gridY"] == @mapping["gridY"] &&
          properties["updateTime"].is_a?(String)
        return failed(code: "invalid_grid") unless valid

        Time.iso8601(properties["updateTime"])
        successful(result.value)
      rescue ArgumentError
        failed(code: "invalid_grid")
      end
    end
  end
end
