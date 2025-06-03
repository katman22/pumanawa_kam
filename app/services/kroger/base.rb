# app/services/kroger/base.rb
module Kroger
  class Base < ApplicationService
    BASE_URL = "https://api.kroger.com/v1"

    attr_reader :token

    def initialize(token:)
      @token = token
    end

    def get(uri)
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(build_request(uri))
      end

      return failed_response(response) unless response.is_a?(Net::HTTPSuccess)

      parse_response(response)
    end

    def build_request(uri)
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{token}"
      req["Accept"] = "application/json"
      req
    end

    def parse_response(response)
      body = JSON.parse(response.body)
      { success: true, data: body }
    rescue JSON::ParserError => e
      Rails.logger.warn("Kroger JSON parse error: #{e.message}")
      { success: false, error: "Unable to parse response", raw: response.body }
    end

    def failed_response(response)
      Rails.logger.warn("Kroger API request failed: #{response.code} #{response.body}")
      { success: false, error: "API call failed", code: response.code, raw: response.body }
    end
  end
end
