namespace :weather_monitoring do
  desc "Brighton NOAA pilot; dry run by default. PERSIST=1 writes; ENABLE=1 PERSIST=1 explicitly enables Brighton. PROBE=1 demonstrates discovery."
  task brighton: :environment do
    resort = Resort.find_by(slug: "brighton")
    abort "Brighton Resort is missing; no Resort records were changed." unless resort
    persist = ENV["PERSIST"] == "1"
    if ENV["ENABLE"] == "1"
      abort "ENABLE=1 requires PERSIST=1; no monitor was enabled." unless persist

      monitor = ResortWeatherMonitor.find_or_create_by!(resort_id: resort.id)
      monitor.update!(enabled: true)
    end
    result = WeatherMonitoring::EvaluateResort.call(resort: resort, persist: persist, probe: ENV["PROBE"] == "1")
    if result.success?
      value = result.value
      puts JSON.pretty_generate(resort: value[:resort], persisted: value[:persisted],
        source_updated_at: value[:source_updated_at], quality: value.dig(:snapshot, "quality", "state"),
        freshness: value.dig(:snapshot, "quality", "freshness"), snowfall_120h: value.dig(:snapshot, "summary", "snowfall"),
        onset_window: value.dig(:snapshot, "summary", "first_accumulating_snow"),
        cadence: value[:cadence], meaningful_change: value[:change], alerts: value[:alerts])
    else
      puts JSON.pretty_generate(result.to_h)
    end
    abort "Brighton evaluation failed." if result.failure?
  end
end
