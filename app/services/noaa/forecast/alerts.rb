# frozen_string_literal: true

module Noaa
  module Forecast
    class Alerts < ApplicationService
      attr_reader :url

      ALERT_URL = ->(lat, long) { "https://api.weather.gov/alerts/active?point=#{lat.to_f},#{long.to_f}" }

      def initialize(latitude, longitude)
        @latitude = latitude
        @longitude = longitude
        @url = ALERT_URL.call(@latitude, @longitude)
      end

      def call
        response = parse_response(alert_response)
        return failed("Unable to retrieve forecast for #{latitude}, #{longitude}") if response.nil?
        alert_features = response.dig("features")
        return successful({ "alerts" => [] }) unless alert_features
        alerts = Convert::Weather::Noaa::Alerts.call(alert_features)
        successful({ "alerts" => alerts })
      end

      def parse_response(response)
        return nil if response.body.nil? || response.body.empty? || response["status"] == 404
        JSON.parse(response)
      end

      def alert_response
        HTTParty.get(url, headers: noaa_agent_header)
      end

      def noaa_agent_header
        { "User-Agent" => "aura_weather (#{ENV['APPLICATION_EMAIL']})" }
      end
    end
  end
end
