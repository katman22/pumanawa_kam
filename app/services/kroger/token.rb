# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Kroger
  class Token < ApplicationService

    attr_reader :client_id, :client_secret

    TOKEN_URL = "https://api.kroger.com/v1/connect/oauth2/token"

    def initialize
      @client_id = ENV["KROGER_CLIENT_ID"]
      @client_secret = ENV["KROGER_CLIENT_SECRET"]
    end

    def call
      token = Rails.cache.fetch("kroger_token", expires_in: 29.minutes) do
        response = kroger_response
        unless response.is_a?(Net::HTTPSuccess)
          Rails.logger.warn("Token fetch failed: #{response.code} #{response.body}")
          return failed(response)
        end

        json = JSON.parse(response.body) rescue failed("Unable to parse response #{response}")
        json["access_token"]
      end

      successful(token)
    end

    def token_credentials
      {
        "grant_type" => "client_credentials",
        "scope" => "product.compact",
        "client_id" => client_id,
        "client_secret" => client_secret
      }
    end

    def kroger_response
      Net::HTTP.post_form(kroger_uri, token_credentials)
    end

    def kroger_uri
      URI(TOKEN_URL)
    end

  end

end
