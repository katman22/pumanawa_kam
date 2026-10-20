# frozen_string_literal: true

module WeatherMonitoring
  class NormalizeForecast < ApplicationService
    VERSION = 1
    LAYERS = {
      "snowfallAmount" => [ "mm", "accumulation" ],
      "quantitativePrecipitation" => [ "mm", "accumulation" ],
      "probabilityOfPrecipitation" => [ "percent", "probability" ],
      "snowLevel" => [ "m", "state" ], "weather" => [ nil, "weather" ],
      "temperature" => [ "degC", "state" ]
    }.freeze

    def initialize(raw:)
      @raw = raw
    end

    def call
      properties = @raw.is_a?(Hash) && @raw["properties"]
      return failed(code: "invalid_grid") unless properties.is_a?(Hash)

      updated = Time.iso8601(properties.fetch("updateTime")).utc.iso8601
      layers, quality = {}, {}
      LAYERS.each do |name, (unit, semantic)|
        layers[name], quality[name] = normalize_layer(properties[name], name, unit, semantic)
      end
      successful("source_key" => "#{properties['gridId']}/#{properties['gridX']},#{properties['gridY']}",
        "source_updated_at" => updated, "normalization_version" => VERSION,
        "content_sha256" => Digest::SHA256.hexdigest(JSON.generate(canonical(layers))),
        "selected_intervals" => layers, "quality" => { "layers" => quality },
        "source_metadata" => properties.slice("validTimes", "elevation", "gridId", "gridX", "gridY"))
    rescue KeyError, ArgumentError, TypeError
      failed(code: "invalid_grid")
    end

    private

    def normalize_layer(layer, name, unit, semantic)
      return [ [], { "diagnostics" => [ "missing_layer" ] } ] unless layer.is_a?(Hash) && layer["values"].is_a?(Array)

      diagnostics = []
      rows = layer["values"].filter_map do |entry|
        unless entry.is_a?(Hash) && entry.key?("value")
          diagnostics << "invalid_interval"
          next
        end
        start_at, end_at, duration = parse_interval(entry["validTime"])
        unless start_at
          diagnostics << "invalid_duration"
          next
        end
        value, recognized = convert(entry["value"], layer["uom"], unit)
        diagnostics << "unsupported_unit_or_value" unless recognized
        uncertain = semantic == "accumulation" && end_at - start_at != 6.hours
        diagnostics << "uncertain_accumulation_duration" if uncertain
        { "start_at" => start_at.iso8601(start_at.subsec.zero? ? 0 : 6), "end_at" => end_at.iso8601(end_at.subsec.zero? ? 0 : 6),
          "value" => value, "unit" => unit, "source_unit" => layer["uom"],
          "source_value" => entry["value"], "valid_time" => entry["validTime"],
          "duration" => duration, "semantic" => semantic }
      end
      rows = rows.sort_by { |row| [ row["start_at"], row["end_at"] ] }.uniq
      rows.each_cons(2) { |a, b| diagnostics << "conflicting_overlap" if b["start_at"] < a["end_at"] }
      diagnostics << "missing_layer" if rows.empty?
      [ rows, { "diagnostics" => diagnostics.uniq } ]
    end

    def parse_interval(value)
      start, duration = value.to_s.split("/", 2)
      match = /\AP(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?\z/.match(duration.to_s)
      return [] unless match && match.captures.any?(&:present?) && !duration.end_with?("T")

      days, hours, minutes, seconds = match.captures.map { |part| part.to_f }
      length = days * 86400 + hours * 3600 + minutes * 60 + seconds
      return [] unless length.positive? && length.finite?

      start_at = Time.iso8601(start).utc
      [ start_at, start_at + length, duration ]
    rescue ArgumentError, RangeError
      []
    end

    def convert(value, source_unit, canonical_unit)
      if canonical_unit.nil?
        valid = value.nil? || (value.is_a?(Array) && value.all? { |item| item.is_a?(Hash) && (item["weather"].nil? || item["weather"].is_a?(String)) })
        return [ value, valid ]
      end
      conversion = case [ canonical_unit, source_unit ]
      when [ "mm", "wmoUnit:mm" ], [ "m", "wmoUnit:m" ], [ "degC", "wmoUnit:degC" ], [ "percent", "wmoUnit:percent" ] then [ 1, 0 ]
      when [ "mm", "wmoUnit:in" ] then [ 25.4, 0 ]
      when [ "m", "wmoUnit:ft" ] then [ 0.3048, 0 ]
      when [ "degC", "wmoUnit:degF" ] then [ 5.0 / 9, -32 ]
      end
      return [ nil, false ] unless conversion
      return [ nil, true ] if value.nil?
      return [ nil, false ] unless value.is_a?(Numeric) && value.finite?

      converted = ((value + conversion[1]) * conversion[0]).round(6)
      valid = (canonical_unit != "percent" || converted.between?(0, 100)) && (canonical_unit != "mm" || converted >= 0)
      [ valid ? converted : nil, valid ]
    end

    def canonical(value)
      case value
      when Hash then value.sort.to_h.transform_values { |item| canonical(item) }
      when Array then value.map { |item| canonical(item) }
      when Numeric then value.to_f
      else value
      end
    end
  end
end
