# frozen_string_literal: true

module WeatherMonitoring
  # Source recording is independent of consumers. Point provenance is attached
  # only to exact point matches; other consumers require authoritative zone data.
  class ProcessAlertCollection < ApplicationService
    def initialize(query:, detected_at:, since:, collection: nil, observations: nil, through: nil, resorts: nil, queried_at: detected_at)
      @collection, @query, @at, @since, @through, @resorts = collection, query, detected_at, since, through, resorts
      @observations, @queried_at = observations, queried_at
    end

    def call
      if @observations.nil?
        recorded = RecordAlertObservations.call(collection: @collection, zone_ids: [], seen_at: @at, signal_evidence: true)
        return recorded if recorded.failure?

        ids = recorded.value[:records].map(&:id)
      else
        ids = @observations
      end
      # Resort deliberately has no new association for this scheduling feature.
      consumers = @resorts || Resort.where(id: ResortWeatherMonitor.where(enabled: true, provider: "noaa").select(:resort_id))
        .where(slug: EvaluateResort::ALLOWED_RESORT_TYPES)
      points = consumers.each_with_object({}) do |resort, context|
        next unless @query["type"] == "point" && @query["latitude"] == resort.latitude && @query["longitude"] == resort.longitude

        context[resort.id] = { latitude: resort.latitude, longitude: resort.longitude, observation_ids: ids,
          queried_at: @queried_at, since_at: @since, through_at: @through }
      end
      generated = GenerateAlertSignals.call(observations: ids, resorts: consumers.to_a, detected_at: @at, point_matches: points)
      return generated if generated.failure?

      successful(generated.value.merge(observation_count: ids.size))
    end
  end
end
