# frozen_string_literal: true

module Noaa
  module Alerts
    class Fetch < ApplicationService
      def initialize(latitude:, longitude:, active: true, since: nil, through: nil)
        @latitude, @longitude = latitude, longitude
        @active, @since = active, since
        @through = through
      end

      def call
        lat, lon = Float(@latitude), Float(@longitude)
        return failed(code: "invalid_coordinates") unless lat.finite? && lon.finite? && lat.between?(-90, 90) && lon.between?(-180, 180)

        return failed(code: "invalid_alert_window") unless [ true, false ].include?(@active) && (@active || @since.is_a?(Time))
        return failed(code: "invalid_alert_window") if @through && (@active || !@through.is_a?(Time) || @through <= @since)

        url = if @active
          "https://api.weather.gov/alerts?active=true&point=#{lat},#{lon}"
        else
          params = { point: "#{lat},#{lon}", start: @since.utc.iso8601 }
          params[:end] = @through.utc.iso8601 if @through
          "https://api.weather.gov/alerts?#{URI.encode_www_form(params)}"
        end
        features, seen = [], []
        while url
          return failed(code: "alert_pagination_invalid") if seen.include?(url) || seen.size >= 10 || !Noaa::Request.valid_url?(url)
          return failed(code: "alert_pagination_scope_changed") if @through && !same_window?(url, lat, lon)

          seen << url
          result = Noaa::Request.call(url: url)
          return result if result.failure?
          body = result.value["body"]
          return failed(code: "invalid_alert_collection") unless body.is_a?(Hash) && body["features"].is_a?(Array) && body["features"].all? { |item| item.is_a?(Hash) && item["properties"].is_a?(Hash) }

          features.concat(body["features"])
          pagination = body["pagination"]
          return failed(code: "alert_pagination_invalid") unless pagination.nil? || pagination.is_a?(Hash)

          url = pagination&.fetch("next", nil)
          return failed(code: "alert_pagination_invalid") unless url.nil? || (url.is_a?(String) && url.present?)
        end
        successful("features" => features)
      rescue ArgumentError, TypeError
        failed(code: "invalid_coordinates")
      end

      private

      # A completed bounded acquisition cannot silently switch geographic/time
      # scope on a later page. Ambiguous cursor-only URLs fail conservatively.
      # Legacy active/manual fetches retain their existing pagination behavior.
      def same_window?(url, lat, lon)
        uri = URI.parse(url)
        pairs = URI.decode_www_form(uri.query.to_s)
        keys = pairs.map(&:first)
        return false if keys.uniq.size != keys.size || (keys - %w[point start end cursor limit]).any?

        params = pairs.to_h
        return false if params.key?("limit") && !params["limit"].match?(/\A[1-9]\d*\z/)
        return false if params.key?("cursor") && params["cursor"].blank?

        uri.path == "/alerts" && params.fetch("point").split(",").map { |coordinate| Float(coordinate) } == [ lat, lon ] &&
          Time.iso8601(params.fetch("start")) == @since && Time.iso8601(params.fetch("end")) == @through
      rescue KeyError, ArgumentError, TypeError, URI::InvalidURIError
        false
      end
    end
  end
end
