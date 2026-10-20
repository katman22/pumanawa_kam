# frozen_string_literal: true

module WeatherMonitoring
  class ForecastSnapshot < ApplicationService
    def initialize(normalized:, evaluation_at:, window_end: nil, stale_after: 24.hours)
      @data, @start = normalized, evaluation_at.to_time.utc
      @end = window_end ? [ window_end.to_time.utc, @start + 120.hours ].min : @start + 120.hours
      @stale_after = stale_after
    end

    def call
      return failed(code: "invalid_window") unless @end > @start

      layers = @data.fetch("selected_intervals")
      coverage = layers.to_h { |name, rows| [ name, layer_quality(name, rows) ] }
      age = @start - Time.iso8601(@data.fetch("source_updated_at"))
      freshness = age < -5.minutes ? "future_source" : (age > @stale_after ? "stale" : "fresh")
      snow_quality = coverage.fetch("snowfallAmount")
      state = freshness == "fresh" ? snow_quality["state"] : "unknown"
      rows = layers.fetch("snowfallAmount")
      total = accumulation(rows, @start, @end, snow_quality)
      buckets = [ [ 0, 24 ], [ 24, 48 ], [ 48, 72 ], [ 72, 120 ] ].map do |low, high|
        left, right = @start + low.hours, [ @start + high.hours, @end ].min
        next if right <= left

        q = layer_quality("snowfallAmount", rows, left, right)
        accumulation(rows, left, right, q).merge("hours" => [ low, high ])
      end.compact
      if freshness != "fresh"
        [ total, *buckets ].each { |bucket| bucket.merge!("state" => "unknown", "amount_mm" => nil, "upper_mm" => nil) }
      end
      usable_snow = snow_quality["diagnostics"].empty?
      first_snow = usable_snow && overlapping(rows).find { |row| row["value"].is_a?(Numeric) && row["value"] > 0 }
      weather = coverage["weather"]["diagnostics"].empty? && overlapping(layers["weather"]).find do |row|
        row["value"].is_a?(Array) && row["value"].any? { |item| %w[snow snow_showers].include?(item["weather"]) }
      end
      pop = context_values(layers["probabilityOfPrecipitation"], coverage["probabilityOfPrecipitation"])
      levels = context_values(layers["snowLevel"], coverage["snowLevel"])
      summary = { "evaluation_at" => @start.iso8601, "window_start" => @start.iso8601, "window_end" => @end.iso8601,
        "snowfall" => total, "buckets" => buckets, "first_possible_snow" => onset(weather),
        "first_accumulating_snow" => onset(first_snow), "maximum_pop_percent" => pop.max,
        "snow_level_m" => { "minimum" => levels.min, "maximum" => levels.max },
        "calculation_method" => "disjoint_interval_allocation_bounds", "complete" => state == "complete" }
      successful("summary" => summary, "quality" => { "state" => state, "freshness" => freshness,
        "source_age_seconds" => age, "layers" => coverage })
    rescue KeyError, ArgumentError, TypeError
      failed(code: "invalid_normalized_forecast")
    end

    private

    def overlapping(rows, left = @start, right = @end)
      rows.select { |row| Time.iso8601(row["start_at"]) < right && Time.iso8601(row["end_at"]) > left }
    end

    def layer_quality(name, rows, left = @start, right = @end)
      diagnostics = @data.dig("quality", "layers", name, "diagnostics") || []
      known = diagnostics.empty? ? overlapping(rows, left, right).reject { |row| row["value"].nil? } : []
      cursor, seconds, gaps = left, 0, []
      known.each do |row|
        a, b = [ Time.iso8601(row["start_at"]), left ].max, [ Time.iso8601(row["end_at"]), right ].min
        gaps << { "start_at" => cursor.iso8601, "end_at" => a.iso8601 } if a > cursor
        seconds += [ b - [ a, cursor ].max, 0 ].max
        cursor = [ cursor, b ].max
      end
      gaps << { "start_at" => cursor.iso8601, "end_at" => right.iso8601 } if cursor < right
      state = seconds == right - left ? "complete" : (seconds.positive? ? "partial" : "unknown")
      { "state" => state, "coverage_seconds" => seconds, "gaps" => gaps, "diagnostics" => diagnostics }
    end

    def accumulation(rows, left, right, quality)
      lower, crossing = 0.0, 0.0
      if quality["diagnostics"].empty?
        overlapping(rows, left, right).each do |row|
          next if row["value"].nil?
          if Time.iso8601(row["start_at"]) >= left && Time.iso8601(row["end_at"]) <= right
            lower += row["value"]
          else
            crossing += row["value"]
          end
        end
      end
      upper = quality["state"] == "complete" ? (lower + crossing).round(6) : nil
      { "start_at" => left.iso8601, "end_at" => right.iso8601, "state" => quality["state"],
        "coverage_seconds" => quality["coverage_seconds"], "lower_mm" => lower.round(6), "upper_mm" => upper,
        "amount_mm" => upper && upper == lower.round(6) ? upper : nil }
    end

    def onset(row)
      row ? row.slice("start_at", "end_at") : nil
    end

    def context_values(rows, quality)
      return [] unless quality["diagnostics"].empty?

      overlapping(rows).filter_map { |row| row["value"] }
    end
  end
end
