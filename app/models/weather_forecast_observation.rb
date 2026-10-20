class WeatherForecastObservation < ApplicationRecord
  belongs_to :resort
  validates :provider, :source_key, :source_updated_at, :first_fetched_at, :forecast_window_start, :forecast_window_end, :content_sha256, presence: true
  validates :normalization_version, numericality: { only_integer: true, greater_than: 0 }
  validates :content_sha256, format: { with: /\A[0-9a-f]{64}\z/ }
  validate :valid_window

  def readonly?
    persisted?
  end

  def normalized
    { "selected_intervals" => selected_intervals, "quality" => quality, "source_key" => source_key,
      "source_updated_at" => source_updated_at.iso8601, "normalization_version" => normalization_version,
      "content_sha256" => content_sha256, "source_metadata" => source_metadata }
  end

  private

  def valid_window
    if forecast_window_start && forecast_window_end && forecast_window_end <= forecast_window_start
      errors.add(:forecast_window_end, "must follow start")
    end
  end
end
