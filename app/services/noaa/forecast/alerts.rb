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

        features = response.dig("features") || []
        alerts = features.map do |feature|
          props = feature["properties"]

          {
            effective: props["effective"],
            onset: props["onset"],
            expires: props["expires"],
            ends: props["ends"],
            status: props["status"],
            message_type: props["messageType"],
            category: props["category"],
            severity: props["severity"],
            certainty: props["certainty"],
            urgency: props["urgency"],
            event: props["event"],
            sender_name: props["senderName"],
            sender: props["sender"],
            headline: props["headline"],
            description: props["description"],
            instruction: props["instruction"],
            response: props["response"]
          }
        end
        successful({ "alerts" => alerts })
      end

      def parse_response(response)
        return nil if response.nil? || response["status"] == 404
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

# app/services/alerts/fetch_alerts.rb
module Alerts
  class FetchAlerts
    NOAA_URL = "https://api.weather.gov/alerts/active".freeze

    def self.call(lat:, lon:)
      uri = URI("#{NOAA_URL}?point=#{lat},#{lon}")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        request = Net::HTTP::Get.new(uri)
        request['User-Agent'] = "AuraWeather (support@yourapp.com)"
        http.request(request)
      end

      json = JSON.parse(response.body)
      features = json.dig("features") || []

      alerts = features.map do |feature|
        props = feature["properties"]

        {
          effective: props["effective"],
          onset: props["onset"],
          expires: props["expires"],
          ends: props["ends"],
          status: props["status"],
          message_type: props["messageType"],
          category: props["category"],
          severity: props["severity"],
          certainty: props["certainty"],
          urgency: props["urgency"],
          event: props["event"],
          sender_name: props["senderName"],
          sender: props["sender"],
          headline: props["headline"],
          description: props["description"],
          instruction: props["instruction"],
          response: props["response"]
        }
      end

      alerts
    rescue => e
      Rails.logger.error("NOAA alert fetch failed: #{e.message}")
      []
    end
  end
end

