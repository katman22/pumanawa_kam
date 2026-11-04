# frozen_string_literal: true

module WeatherMonitoring
  class AlertAcquisitionPolicy < ApplicationService
    DEFAULTS = { interval: 10.minutes, lookback: 24.hours, overlap: 30.minutes,
      horizon: 6.days, lease: 5.minutes, max_backoff: 6.hours }.freeze

    def initialize(at:, watermark: nil, initial_window_start_at: nil, failures: 0, provider_retry_at: nil, policy: {})
      @at, @watermark, @failures, @provider_retry = at.utc, watermark, failures, provider_retry_at
      @initial_start = initial_window_start_at
      @policy = DEFAULTS.merge(policy)
    end

    def call
      return failed(code: "invalid_acquisition_policy") unless @policy.values.all? { |duration| duration.to_f.positive? } &&
        @policy[:horizon] >= @policy[:lookback] && @failures >= 0 && (!@watermark || @watermark <= @at) && (!@initial_start || @initial_start <= @at)

      # Match the API's explicitly requested timestamp precision.
      through = @at.change(usec: 0)
      floor = through - @policy[:horizon]
      recovery_start = @watermark ? @watermark - @policy[:overlap] : @initial_start
      desired = recovery_start ? [ through - @policy[:lookback], recovery_start ].min : through - @policy[:lookback]
      from = [ floor, desired ].max
      anchor = @watermark || @initial_start
      gap = anchor && anchor < from ? { "from" => anchor.utc.iso8601, "through" => from.iso8601 } : nil
      delay = [ @policy[:interval] * (2**[ [ @failures - 1, 0 ].max, 10 ].min), @policy[:max_backoff] ].min
      successful(from: from, through: through, coverage_gap: gap,
        coverage_status: gap ? "recovery_gap" : (@watermark ? "bounded_window" : "initial_window"),
        next_check_at: @at + @policy[:interval], lease_expires_at: @at + @policy[:lease],
        retry_at: [ @at + delay, @provider_retry || @at ].max)
    end
  end
end
