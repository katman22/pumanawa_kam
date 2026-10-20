# frozen_string_literal: true

module WeatherMonitoring
  class RecordAlertObservations < ApplicationService
    EVENTS = [ "Winter Storm Watch", "Winter Storm Warning", "Winter Weather Advisory", "Blizzard Warning" ].freeze

    def initialize(collection:, zone_ids:, seen_at:, persist: true)
      @collection, @zones, @at, @persist = collection, zone_ids, seen_at, persist
    end

    def call
      records, changed, active, revisions = [], [], [], []
      features = @collection.fetch("features")
      return failed(code: "invalid_alert_evidence") unless features.is_a?(Array) && features.all? { |item| item.is_a?(Hash) && item["properties"].is_a?(Hash) }
      eligible = features.select do |feature|
        properties = feature["properties"]
        properties["status"] == "Actual" && EVENTS.include?(properties["event"]) && %w[Alert Update Cancel].include?(properties["messageType"])
      end
      return failed(code: "invalid_alert_evidence") unless eligible.all? { |feature| feature["properties"]["id"].is_a?(String) && feature["properties"]["id"].present? }

      WeatherAlertObservation.transaction do
        eligible.each do |feature|
          properties = feature.fetch("properties")

          zones = Array(properties["affectedZones"]).map { |zone| String(zone).split("/").last } | Array(properties.dig("geocode", "UGC"))
          next if (zones & @zones).empty?

          attributes = attributes_for(properties, zones)
          key = attributes.slice(:provider, :source_identifier, :content_sha256)
          revisions << "#{attributes[:source_identifier]}:#{attributes[:content_sha256]}"
          existing = WeatherAlertObservation.find_by(key)
          record = existing || (@persist ? WeatherAlertObservation.create_or_find_by!(key) { |row| row.assign_attributes(attributes.except(*key.keys)) } : nil)
          changed << "#{attributes[:source_identifier]}:#{attributes[:content_sha256]}" unless existing || (record && !record.previously_new_record?)
          records << record if record
          ending = properties["messageType"] == "Cancel" || Array(properties.dig("parameters", "VTEC")).any? { |vtec| vtec.to_s.match?(/\.((CAN)|(EXP))\./) }
          expires = attributes[:expires_at]
          ends_at = attributes[:ends_at]
          active << attributes[:source_identifier] unless ending || (expires && expires <= @at) || (ends_at && ends_at <= @at) || properties["replacedBy"].present?
        end
      end
      successful(records: records, changed: changed.uniq, revisions: revisions.uniq, active_identifiers: active.uniq)
    rescue KeyError, ArgumentError, TypeError, ActiveRecord::RecordInvalid => error
      failed(code: "invalid_alert_evidence", error_class: error.class.name)
    end

    private

    def attributes_for(properties, zones)
      evidence = properties.slice("headline", "areaDesc", "sender", "references", "replacedBy", "replacedAt", "parameters", "geocode")
      content = properties.slice("id", "sent", "event", "status", "messageType", "effective", "onset", "expires", "ends", "severity", "certainty", "urgency").merge("zones" => zones.sort, "evidence" => evidence)
      attributes = { provider: "noaa", source_identifier: properties.fetch("id"),
        content_sha256: Digest::SHA256.hexdigest(JSON.generate(canonical(content))), first_seen_at: @at,
        source_sent_at: Time.iso8601(properties.fetch("sent")), event: properties["event"], status: properties["status"],
        message_type: properties["messageType"], severity: properties["severity"], certainty: properties["certainty"], urgency: properties["urgency"],
        affected_zone_ids: zones.sort, evidence: evidence }
      %w[effective onset expires ends].each { |key| attributes["#{key}_at".to_sym] = Time.iso8601(properties[key]) if properties[key] }
      attributes
    end

    def canonical(value)
      case value
      when Hash then value.sort.to_h.transform_values { |item| canonical(item) }
      when Array then value.map { |item| canonical(item) }
      else value
      end
    end
  end
end
