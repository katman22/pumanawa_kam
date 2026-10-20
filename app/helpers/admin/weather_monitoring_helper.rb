module Admin::WeatherMonitoringHelper
  WEATHER_LEVEL_LABELS = {
    "quiet" => "Quiet forecast", "far" => "Snow candidate 3–5 days away",
    "approaching" => "Snow candidate 48–72 hours away", "near" => "Snow candidate within 48 hours",
    "active" => "Forecast snow window active", "accelerated" => "Accelerated reassessment",
    "unknown" => "Unknown forecast — earlier retry"
  }.freeze
  WEATHER_REASON_LABELS = {
    "incomplete_or_stale" => "Incomplete or stale source", "forecast_active" => "Forecast snow window active",
    "snow_amount_changed" => "Meaningful forecast snowfall change", "onset_shifted" => "Accumulation onset shifted",
    "entered_48h" => "Storm entered the 48-hour window", "forecast_became_active" => "Forecast became active",
    "grid_probe_changed" => "Grid revision changed during discovery", "alert_reassessment" => "Relevant NOAA alert changed",
    "no_baseline" => "No previous forecast baseline", "incompatible_source" => "Source/grid or normalization version changed",
    "unknown" => "Insufficient evidence to compare forecasts", "compared" => "Compared compatible forecast windows"
  }.freeze

  def weather_state(value)
    state = value.presence || "unknown"
    style = case state.to_s
    when "complete", "fresh", "enabled" then "good"
    when "partial", "stale", "future_source", "degraded" then "caution"
    else "neutral"
    end
    content_tag(:span, state.to_s.humanize, class: "weather-state weather-state--#{style}", data: { state: state })
  end

  def weather_time(value, mapping: {})
    return "Not recorded" if value.blank?

    time = value.is_a?(String) ? Time.iso8601(value) : value.to_time
    zone = ActiveSupport::TimeZone[mapping["timeZone"].to_s] || ActiveSupport::TimeZone["America/Denver"]
    content_tag(:time, time.in_time_zone(zone).strftime("%b %-d, %Y %H:%M %Z"), datetime: time.utc.iso8601, title: time.utc.iso8601)
  rescue ArgumentError, TypeError
    "Invalid timestamp"
  end

  def weather_window(value, mapping: {})
    return "UNKNOWN" unless value.is_a?(Hash) && value["start_at"] && value["end_at"]

    safe_join([ weather_time(value["start_at"], mapping: mapping), weather_time(value["end_at"], mapping: mapping) ], " – ")
  end

  def weather_source_age(value)
    return "UNKNOWN" unless value
    return "Source time is in the future" if value > Time.current

    "#{time_ago_in_words(value)} old"
  end

  def weather_inches_number(mm)
    inches = mm.to_d / 25.4
    return "<0.1" if inches.positive? && inches < 0.1

    number_with_precision(inches, precision: 1, strip_insignificant_zeros: true)
  end

  def weather_snowfall(value, freshness: nil)
    return "STALE · amount unknown" if freshness == "stale"
    return "UNKNOWN" unless value.is_a?(Hash)
    if value["state"] == "partial"
      lower = value["lower_mm"]
      return "PARTIAL · at least #{weather_inches_number(lower)}″; total unknown" if lower.is_a?(Numeric) && lower.positive?

      return "PARTIAL · total unknown"
    end
    return "UNKNOWN" unless value["state"] == "complete" && freshness != "future_source"

    amount = value["amount_mm"]
    return "#{weather_inches_number(amount)}″" if amount.is_a?(Numeric)

    lower, upper = value.values_at("lower_mm", "upper_mm")
    return "UNKNOWN" unless lower.is_a?(Numeric) && upper.is_a?(Numeric)

    "#{weather_inches_number(lower)}–#{weather_inches_number(upper)}″ (bounded)"
  end

  def weather_level_label(level)
    WEATHER_LEVEL_LABELS.fetch(level.to_s) { level.presence&.humanize || "Not evaluated" }
  end

  def weather_reason_label(code)
    WEATHER_REASON_LABELS.fetch(code.to_s) { code.to_s.humanize }
  end

  def weather_decision_labels(monitor)
    decision = monitor.last_decision
    labels = Array(decision["reasons"]).map { |code| weather_reason_label(code) }
    labels << weather_level_label(monitor.monitoring_level) if labels.empty?
    change = decision.dig("change", "disposition")
    labels << weather_reason_label(change) if change.present?
    labels.uniq
  end

  def weather_overall_quality(quality)
    quality["freshness"] == "stale" ? "stale" : quality["state"].presence || "unknown"
  end

  def weather_interval_value(row)
    value = row["value"]
    return "UNKNOWN (null)" if value.nil?
    return value.to_s unless value.is_a?(Array)

    value.map { |item| item.is_a?(Hash) ? item.slice("coverage", "weather", "intensity").values.compact.join(" · ").presence || "No weather type specified" : item.to_s }.join("; ")
  end
  def weather_monitor_snowfall(monitor, observation)
    return "UNKNOWN" unless observation

    state = monitor.last_decision["quality"]
    return "#{state.upcase} · inspect recorded evidence" if %w[unknown partial].include?(state)

    weather_snowfall(observation.summary["snowfall"], freshness: observation.quality["freshness"])
  end

  def weather_observation_window(observation, mapping: {})
    return "UNKNOWN" unless observation

    safe_join([ weather_time(observation.forecast_window_start, mapping: mapping), weather_time(observation.forecast_window_end, mapping: mapping) ], " – ")
  end

  def weather_snow_level(range)
    return "UNKNOWN" unless range.is_a?(Hash) && range["minimum"].is_a?(Numeric) && range["maximum"].is_a?(Numeric)

    "#{number_with_precision(range['minimum'], precision: 0)}–#{number_with_precision(range['maximum'], precision: 0)} m"
  end

  def weather_grid_elevation(metadata)
    elevation = metadata&.fetch("elevation", nil)
    return "Not recorded" unless elevation.is_a?(Hash) && elevation["value"].is_a?(Numeric)

    unit = elevation["unitCode"] == "wmoUnit:m" ? "m" : elevation["unitCode"]
    "#{number_with_precision(elevation['value'], precision: 0)} #{unit} (NOAA grid)"
  end

  def weather_coverage(seconds)
    return "UNKNOWN" unless seconds.is_a?(Numeric)

    "#{number_with_precision(seconds / 3600.0, precision: 1, strip_insignificant_zeros: true)} h known"
  end

  def weather_alert_status(monitor)
    state = monitor.last_decision.dig("alerts", "state")
    return "DEGRADED · last known #{monitor.active_alert_identifiers.size} identifiers" if state == "degraded"
    return "UNKNOWN · not checked" unless monitor.last_alert_checked_at

    "#{monitor.active_alert_identifiers.size} identifiers listed at last probe"
  end
end
