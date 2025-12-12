# app/services/udot/mountain_passes.rb
module Udot
  class MountainPasses < ApplicationService
    CACHE_TTL = 5.minutes

    attr_reader :resort

    def initialize(resort:)
      @resort = resort
    end

    def call
      key = "udot:mountain_passes:#{resort.slug}"

      data = Rails.cache.fetch(key, expires_in: CACHE_TTL, race_condition_ttl: 10) do
        fetch_pass_data
      end

      return failed("No mountain pass data available") if data.blank?
      successful(data)
    rescue => e
      Rails.logger.error("[UDOT MountainPasses] #{e.class}: #{e.message}")
      failed("No mountain pass data available")
    end

    private

    def fetch_pass_data
      resp = Udot::FetchType.new(type: "mountainpasses", filter: filter(resort, "signs")).call
      return nil if resp.failure?

      normalize(resp.value)
    end

    def normalize(upstream)
      Array(upstream).map do |pass|
        seasonal = Array(pass["SeasonalInfo"]).first
        {
          id: pass["Id"],
          type: "mountain_pass",
          name: pass["Name"],
          roadway: pass["Roadway"],
          elevation_ft: pass["MaxElevation"]&.to_i,

          # Derived status
          status: seasonal_status(seasonal),
          seasonal_closure_title: pass["SeasonalClosureTitle"],
          seasonal_description: seasonal["SeasonalClosureDescription"],

          # Conditions
          surface_status: pass["SurfaceStatus"],
          visibility_miles: pass["Visibility"],

          # Weather
          air_temp_f: pass["AirTemperature"]&.to_i,
          surface_temp_f: pass["SurfaceTemp"]&.to_i,
          wind: {
            direction: pass["WindDirection"],
            speed_mph: pass["WindSpeed"]&.to_i,
            gust_mph: pass["WindGust"]&.to_i
          },

          # Forecast blob (keep raw — parsing later if desired)
          forecast: parse_forecast(pass["Forecasts"]),

          # Location
          latitude: pass["Latitude"],
          longitude: pass["Longitude"],
          station: pass["StationName"]
        }
      end
    end

    def seasonal_status(seasonal)
      return "open" if seasonal.nil?
      seasonal["SeasonalClosureStatus"]&.downcase || "unknown"
    end

    def parse_forecast(forecasts)
      return [] if forecasts.blank?

      forecasts.split("|").map do |segment|
        time, text = segment.split(";", 2)
        {
          period: time,
          summary: text
        }
      end
    end

    def filter(resort, kind)
      filter = resort.resort_filters.select { |filter| filter.kind == kind }.first
      filter.parsed_data
    end
  end
end
