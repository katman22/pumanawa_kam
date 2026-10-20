# frozen_string_literal: true

module WeatherMonitoring
  class EvaluateCadence < ApplicationService
    DEFAULTS = { quiet: 72.hours, far: 12.hours, approaching: 6.hours, near: 4.hours,
      accelerated: 1.hour, unknown: 1.hour, acceleration: 6.hours, probe: 12.hours }.freeze

    def initialize(snapshot:, evaluation_at:, change: {}, acceleration_until: nil, alert_wake: false,
      existing_next_check_at: nil, probe: false, grid_changed: false, policy: {})
      @snapshot, @at, @change = snapshot, evaluation_at, change
      @until, @alert, @existing, @probe, @grid_changed = acceleration_until, alert_wake, existing_next_check_at, probe, grid_changed
      @policy = DEFAULTS.merge(policy)
    end

    def call
      quality, summary = @snapshot.fetch("quality"), @snapshot.fetch("summary")
      onset = summary["first_accumulating_snow"] || summary["first_possible_snow"]
      lead = onset && Time.iso8601(onset["start_at"]) - @at
      reasons = []
      if quality["state"] != "complete"
        level, delay = "unknown", @policy[:unknown]
        reasons << "incomplete_or_stale"
      elsif lead && lead <= 0
        level, delay = "active", @policy[:accelerated]
        reasons << "forecast_active"
      elsif @change["meaningful_change"] == true || (@until && @until > @at)
        level, delay = "accelerated", @policy[:accelerated]
        @until = @at + @policy[:acceleration] if @change["meaningful_change"] == true && (!@until || @until <= @at)
        reasons.concat(@change["reasons"] || [])
      elsif lead
        level, delay = if lead < 48.hours
          [ "near", @policy[:near] ]
        elsif lead < 72.hours
          [ "approaching", @policy[:approaching] ]
        else
          [ "far", @policy[:far] ]
        end
      elsif summary.dig("snowfall", "upper_mm") == 0
        level, delay = "quiet", @policy[:quiet]
      else
        level, delay = "unknown", @policy[:unknown]
      end
      due = @at + delay
      if @probe
        due = [ @existing || due, due ].min
        due = [ due, @at ].min if @grid_changed
        reasons << "grid_probe_changed" if @grid_changed
      end
      if @alert
        due = [ due, @existing || due, @at ].min
        reasons << "alert_reassessment"
      end
      successful("monitoring_level" => level, "next_check_at" => due, "next_probe_at" => @at + [ @policy[:probe], delay ].min,
        "acceleration_until" => @until && @until > @at ? @until : nil, "reasons" => reasons)
    rescue KeyError, ArgumentError, TypeError
      failed(code: "invalid_cadence_input")
    end
  end
end
