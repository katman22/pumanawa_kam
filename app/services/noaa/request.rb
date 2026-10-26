# frozen_string_literal: true

module Noaa
  # Shared transport only: no forecast interpretation, caching or persistence.
  class Request < ApplicationService
    TIMEOUT = 6

    def initialize(url:, headers: {})
      @url, @headers = url, headers
    end

    def self.valid_url?(url)
      uri = URI.parse(url.to_s)
      uri.scheme == "https" && uri.host == "api.weather.gov" && uri.port == 443 && uri.userinfo.nil?
    rescue URI::InvalidURIError
      false
    end

    def call
      return failed(code: "invalid_url") unless self.class.valid_url?(@url)

      2.times do |attempt|
        begin

          response = HTTParty.get(@url, headers: {
            "User-Agent" => "canyon_traveller (#{ENV['APPLICATION_EMAIL']})",
            "Accept" => "application/geo+json"
          }.merge(normalize_request_headers(@headers)), timeout: TIMEOUT, follow_redirects: false)
          status = response.code.to_i
          headers = response.headers.to_h.transform_keys { |key| key.to_s.downcase }.transform_values do |values|
            values.is_a?(Array) && values.one? ? values.first : values
          end
          if status >= 500 && attempt.zero?
            sleep 0.2
            next
          end
          return failed(code: "rate_limited", retry_at: retry_at(headers["retry-after"])) if status == 429
          return successful("status" => 304, "headers" => headers) if status == 304
          return failed(code: "http_#{status}") unless status == 200

          body = JSON.parse(response.body)
          return failed(code: "invalid_payload") unless body.is_a?(Hash) && !body.key?("status")

          return successful("status" => status, "headers" => headers, "body" => body)
        rescue Timeout::Error, SocketError, Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::ETIMEDOUT, EOFError, OpenSSL::SSL::SSLError, HTTParty::Error => error
          return failed(code: "transport_error", error_class: error.class.name) unless attempt.zero?

          sleep 0.2
        rescue JSON::ParserError, TypeError
          return failed(code: "malformed_json")
        end
      end
    end

    private

    def retry_at(value)
      return Time.current + value.to_i.seconds if value.to_s.match?(/\A\d+\z/)

      Time.httpdate(value.to_s)
    rescue ArgumentError
      Time.current + 15.minutes
    end

    def normalize_request_headers(headers)
      headers.transform_values do |value|
        value.is_a?(Array) && value.one? ? value.first : value
      end
    end
  end
end
