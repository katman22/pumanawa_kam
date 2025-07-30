# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "httparty"

module OpenWeather
  module Forecast
    class Discussion < Base
      def call
        overview_response = OpenWeather::Forecast::Overview.new(latitude: @latitude, longitude: @longitude, clear_cache: true).call
        return failed(overview_response.value) if overview_response.failure?

        current_overview = overview_response.value
        current_date = current_overview["date"]
        next_date = DateTime.parse(current_date) + 1
        next_response = OpenWeather::Forecast::Overview.new(latitude: @latitude, longitude: @longitude, date: next_date, clear_cache: true).call
        return failed(next_response.value) if next_response.failure?

        next_overview = next_response.value
        alerts_response = OpenWeather::Forecast::Alerts.new(latitude: @latitude, longitude: @longitude).call
        return failed(alerts_response.value) if alerts_response.failure?

        alerts = alerts_response.value["alerts"]
        converted_data = Convert::Weather::OpenWeather::Discussion.({ short_term: current_overview["weather_overview"], long_term: next_overview["weather_overview"], alerts: alerts })
        successful(converted_data)
      end
    end
  end
end
