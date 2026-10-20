# frozen_string_literal: true

module WeatherMonitoring
  class DetectMeaningfulChange < ApplicationService
    DEFAULTS = { absolute_mm: 50.8, percent: 30, relative_floor_mm: 25.4, substantial_mm: 152.4, onset_shift: 6.hours }.freeze

    def initialize(current:, previous: nil, evaluation_at:, previous_evaluation_at: nil, policy: {})
      @current, @previous, @at = current, previous, evaluation_at
      @previous_at = previous_evaluation_at
      @policy = DEFAULTS.merge(policy)
    end

    def call
      return successful("disposition" => "no_baseline", "meaningful_change" => nil, "reasons" => []) unless @previous
      unless @current["source_key"] == @previous["source_key"] && @current["normalization_version"] == @previous["normalization_version"]
        return successful("disposition" => "incompatible_source", "meaningful_change" => nil, "reasons" => [])
      end
      ends = [ @current, @previous ].map { |data| data.fetch("selected_intervals").fetch("snowfallAmount").map { |row| Time.iso8601(row["end_at"]) }.max }
      return unknown unless ends.all? && ends.min > @at

      results = [ @current, @previous ].map { |data| ForecastSnapshot.call(normalized: data, evaluation_at: @at, window_end: ends.min) }
      return unknown unless results.all?(&:success?) && results.all? { |r| r.value.dig("quality", "state") == "complete" }

      current, previous = results.map { |result| result.value["summary"] }
      a, b = current["snowfall"], previous["snowfall"]
      delta = [ a["lower_mm"] - b["upper_mm"], b["lower_mm"] - a["upper_mm"], 0 ].max.round(6)
      percent = b["upper_mm"].positive? ? (delta / b["upper_mm"] * 100).round(6) : 0
      reasons = []
      if delta >= @policy[:absolute_mm] || (delta >= @policy[:relative_floor_mm] && percent >= @policy[:percent] && [ a["lower_mm"], b["lower_mm"] ].max >= @policy[:substantial_mm])
        reasons << "snow_amount_changed"
      end
      onset, old_onset = current["first_accumulating_snow"], previous["first_accumulating_snow"]
      if onset && old_onset && (Time.iso8601(onset["start_at"]) - Time.iso8601(old_onset["start_at"])).abs >= @policy[:onset_shift]
        reasons << "onset_shifted"
      end
      if @previous_at && onset
        earlier = ForecastSnapshot.call(normalized: @previous, evaluation_at: @previous_at)
        old = earlier.success? && earlier.value.dig("summary", "first_accumulating_snow")
        if old
          was_far = Time.iso8601(old["start_at"]) - @previous_at >= 48.hours
          reasons << "entered_48h" if was_far && Time.iso8601(onset["start_at"]) - @at < 48.hours
          reasons << "forecast_became_active" if Time.iso8601(old["start_at"]) > @previous_at && Time.iso8601(onset["start_at"]) <= @at
        end
      end
      successful("disposition" => "compared", "meaningful_change" => reasons.any?, "reasons" => reasons,
        "minimum_absolute_change_mm" => delta.round(6), "comparison_window" => current.slice("window_start", "window_end"))
    rescue KeyError, ArgumentError, TypeError
      unknown
    end

    private

    def unknown
      successful("disposition" => "unknown", "meaningful_change" => nil, "reasons" => [])
    end
  end
end
