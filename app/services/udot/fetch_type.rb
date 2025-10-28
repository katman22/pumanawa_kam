# frozen_string_literal: true

require "digest"

module Udot
  class FetchType < ApplicationService
    attr_reader :type, :filter

    UDOT_KEY = ENV.fetch("UDOT_KEY")
    UDOT_API = ENV.fetch("UDOT_API")

    CACHE_TTL_SECONDS = 300 # 5 min; adjust as needed
    RACE_TTL_SECONDS  = 10
    HTTP_TIMEOUT      = 6   # total timeout for HTTParty (seconds)
    RETRIES           = 1   # one retry on transient errors

    def initialize(type:, filter: {})
      @type   = String(type)
      @filter = filter.presence || {}
    end

    def call
      body = fetch_and_cache_udot
      return failed(" UDOT response empty") if body.blank?

      data = parse_json_array(body)
      data = apply_filter(data)
      successful(data)
    rescue => e
      Rails.logger.error("[UDOT FetchType #{type}] #{e.class}: #{e.message}")
      failed(" UDOT fetch failed")
    end

    private

    # ---- Fetch with small retry; only cache successful bodies -----------------
    def fetch_and_cache_udot
      key = cache_key

      Rails.cache.fetch(key, expires_in: CACHE_TTL_SECONDS, race_condition_ttl: RACE_TTL_SECONDS, skip_nil: true) do
        body = http_get_body
        # Only cache if we actually got a non-empty body
        body.presence
      end
    end

    def http_get_body
      url     = "#{UDOT_API}/#{type}"
      query   = { key: UDOT_KEY }
      headers = { "Accept" => "application/json" }

      attempts = 0
      begin
        attempts += 1
        resp = HTTParty.get(url, query: query, headers: headers, timeout: HTTP_TIMEOUT)

        code = resp.code.to_i rescue 0
        b    = resp&.body.to_s

        unless code.between?(200, 299)
          raise "HTTP #{code} from UDOT #{type}"
        end
        if b.strip.empty?
          raise "Empty body from UDOT #{type}"
        end

        b
      rescue => e
        if attempts <= RETRIES
          Rails.logger.warn("[UDOT FetchType #{type}] retrying after error: #{e.message}")
          sleep 0.2
          retry
        end
        Rails.logger.error("[UDOT FetchType #{type}] giving up: #{e.message}")
        nil
      end
    end

    # ---- Helpers --------------------------------------------------------------
    def parse_json_array(body)
      parsed = JSON.parse(body)
      # UDOT returns arrays for cameras/signs/etc; normalize to array
      parsed.is_a?(Array) ? parsed : Array(parsed)
    rescue JSON::ParserError => e
      Rails.logger.error("[UDOT FetchType #{type}] JSON parse error: #{e.message}")
      []
    end

    def apply_filter(data)
      return data if filter.blank?

      data.select do |item|
        next false unless item.is_a?(Hash)
        filter.all? do |k, v|
          # tolerate string/symbol keys; allow substring match on string values
          val = item[k.to_s] || item[k.to_sym]
          case val
          when String
            val.downcase.include?(v.to_s.downcase)
          when Array
            val.map(&:to_s).any? { |s| s.downcase.include?(v.to_s.downcase) }
          else
            val.to_s.downcase.include?(v.to_s.downcase)
          end
        end
      end
    end

    def cache_key
      f = filter.present? ? Digest::SHA256.hexdigest(filter.to_json) : "nofilter"
      "udot:v2:#{type}:#{f}"
    end
  end
end
