# frozen_string_literal: true

module WeatherMonitoring
  class GenerateAlertSignals < ApplicationService
    MATERIAL_FIELDS = %w[event severity certainty urgency effective_at onset_at expires_at ends_at affected_zone_ids].freeze
    MATERIAL_EVIDENCE = %w[headline description instruction areaDesc affectedZones geometry category response scope language].freeze

    # point_matches is trusted acquisition context supplied by DetectAlertSignals
    # only after a successful NOAA point query, never inferred from areaDesc.
    def initialize(observations:, resorts: nil, point_matches: {}, detected_at: Time.current)
      @observations, @resorts, @point_matches, @at = observations, resorts, point_matches, detected_at
    end

    def call
      return failed(code: "alert_observation_missing") if @observations.nil?

      results = []
      WeatherAlertSignal.transaction(requires_new: true) do
        records = Array(@observations).map do |input|
          id = input.is_a?(WeatherAlertObservation) ? input.id : input
          record = WeatherAlertObservation.find_by(id: id)
          unless record
            @failure = failed(code: "alert_observation_missing")
            raise ActiveRecord::Rollback
          end
          record
        end
        records.uniq(&:id).sort_by(&:id).each do |record|
          # Short source-row lock serializes the same revision across resorts;
          # all HTTP has already finished. Uniqueness is also enforced in SQL.
          record.with_lock { results << generate(record) }
        end
      end
      @failure || successful(outcomes: results, created_count: results.count { |row| row[:disposition] == "created" })
    rescue ActiveRecord::RecordInvalid => error
      failed(code: "alert_signal_invalid", error_class: error.class.name)
    rescue ActiveRecord::ActiveRecordError => error
      failed(code: "alert_signal_persistence_error", error_class: error.class.name)
    end

    private

    def generate(record)
      return skip(record, "unsupported_source") unless record.provider == "noaa" && record.status == "Actual"
      return skip(record, "incomplete_evidence") unless complete?(record)
      return skip(record, "unknown_lifecycle") unless %w[Alert Update Cancel].include?(record.message_type)
      references = record.evidence.fetch("references")
      return skip(record, "missing_references") if record.message_type != "Alert" && references.empty?
      matches = relevant_resorts(record)
      return skip(record, "no_approved_geographic_match") if matches.empty?

      existing = WeatherAlertSignal.find_by(weather_alert_observation_id: record.id)
      return associate(existing, matches, "existing") if existing

      previous = previous_observation(record, references)
      return skip(record, "older_source_revision") if WeatherAlertObservation.where(provider: record.provider, source_identifier: record.source_identifier).where("source_sent_at > ?", record.source_sent_at).exists?
      actions = vtec_actions(record)
      type = signal_type(record, previous, actions)
      return skip(record, type) unless WeatherAlertSignal::TYPES.include?(type)

      signal = WeatherAlertSignal.create_or_find_by!(weather_alert_observation_id: record.id) do |row|
        row.assign_attributes(previous_observation: previous, signal_type: type, detected_at: @at,
          change_details: { "fields" => changed_fields(record, previous), "reference_identifiers" => references.map { |ref| ref["identifier"] },
            "vtec_actions" => actions, "baseline" => previous ? "available" : "unavailable" })
      end
      associate(signal, matches, signal.previously_new_record? ? "created" : "existing")
    end

    def complete?(record)
      evidence = record.evidence
      evidence["signal_evidence_version"] == 1 && evidence["description"].is_a?(String) && evidence.key?("instruction") &&
        (evidence["instruction"].nil? || evidence["instruction"].is_a?(String)) && evidence["scope"] == "Public" &&
        record.severity.present? && record.certainty.present? && record.urgency.present? &&
        evidence["references"].is_a?(Array) && evidence["references"].all? { |ref| ref.is_a?(Hash) && ref["identifier"].is_a?(String) && ref["identifier"].present? }
    end

    def previous_observation(record, references)
      scope = WeatherAlertObservation.where(provider: record.provider)
      earlier = scope.where(source_identifier: record.source_identifier)
        .where("first_seen_at < :at OR (first_seen_at = :at AND id < :id)", at: record.first_seen_at, id: record.id)
        .order(first_seen_at: :desc, id: :desc).detect { |row| complete?(row) }
      return earlier if earlier

      scope.where(source_identifier: references.map { |ref| ref["identifier"] }).where("source_sent_at <= ?", record.source_sent_at)
        .order(source_sent_at: :desc, id: :desc).detect { |row| complete?(row) }
    end

    def signal_type(record, previous, actions)
      if previous&.source_identifier == record.source_identifier && previous.message_type == record.message_type && changed_fields(record, previous).empty?
        prior_actions = vtec_actions(previous)
        return "metadata_only_change" if actions == prior_actions
      end
      return "cancelled" if record.message_type == "Cancel" || (record.message_type == "Update" && actions == [ "CAN" ])
      return "source_replaced" if record.evidence["replacedBy"].present?
      return "expired_evidence" if [ record.expires_at, record.ends_at ].compact.any? { |time| time <= @at } || actions == [ "EXP" ]
      return "corrected" if record.message_type == "Update" && actions == [ "COR" ]
      return "metadata_only_change" if previous && changed_fields(record, previous).empty?
      return "material_content_changed" if previous&.source_identifier == record.source_identifier

      record.message_type == "Alert" ? "issued" : "updated"
    end

    def changed_fields(record, previous)
      return [] unless previous

      MATERIAL_FIELDS.select { |field| record.public_send(field) != previous.public_send(field) } +
        MATERIAL_EVIDENCE.select do |field|
          left, right = record.evidence[field], previous.evidence[field]
          field == "affectedZones" ? Array(left).sort != Array(right).sort : left != right
        end
    end

    def vtec_actions(record)
      Array(record.evidence.dig("parameters", "VTEC")).map do |line|
        line.to_s.strip[/\A\/O\.([A-Z]{3})\.[A-Z]{4}\.[A-Z]{2}\.[A-Z]\.\d{4}\.\d{6}T\d{4}Z-\d{6}T\d{4}Z\/\z/, 1] || "UNKNOWN"
      end.uniq.sort
    end

    def relevant_resorts(record)
      scope = ResortWeatherMonitor.where(enabled: true, provider: "noaa").joins(:resort)
        .where(resorts: { slug: EvaluateResort::ALLOWED_RESORT_TYPES }).includes(:resort)
      scope = scope.where(resort_id: Array(@resorts).map(&:id)) if @resorts
      scope.filter_map do |monitor|
        resort = monitor.resort
        point = @point_matches[resort.id]
        if point && point[:latitude] == resort.latitude && point[:longitude] == resort.longitude && Array(point[:observation_ids]).include?(record.id)
          next [ resort, { "method" => "noaa_point_query", "latitude" => resort.latitude, "longitude" => resort.longitude,
            "queried_at" => point[:queried_at]&.iso8601, "since_at" => point[:since_at]&.iso8601 } ]
        end
        mapping = monitor.mapping
        next unless mapping["latitude"] == resort.latitude && mapping["longitude"] == resort.longitude

        zones = mapping.values_at("forecastZone", "county", "fireWeatherZone").compact.map { |url| url.to_s.split("/").last }
        matched = record.affected_zone_ids & zones
        [ resort, { "method" => "noaa_zone_mapping", "zone_ids" => matched } ] if matched.any?
      end
    end

    def associate(signal, matches, disposition)
      matches.each do |resort, evidence|
        next if WeatherAlertSignalResort.exists?(weather_alert_signal: signal, resort: resort)

        WeatherAlertSignalResort.create_or_find_by!(weather_alert_signal: signal, resort: resort) do |row|
          row.assign_attributes(associated_at: @at, evidence: evidence)
        end
      end
      source = signal.weather_alert_observation
      { observation_id: source.id, source_identifier: source.source_identifier, provider: source.provider,
        event: source.event, message_type: source.message_type, source_sent_at: source.source_sent_at,
        signal_id: signal.id, signal_type: signal.signal_type, detected_at: signal.detected_at,
        changed_fields: signal.change_details["fields"], disposition: disposition,
        resort_ids: matches.map { |resort, _evidence| resort.id } }
    end

    def skip(record, reason)
      { observation_id: record.id, source_identifier: record.source_identifier, disposition: "skipped", reason: reason }
    end
  end
end
