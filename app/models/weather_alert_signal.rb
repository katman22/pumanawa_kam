class WeatherAlertSignal < ApplicationRecord
  TYPES = %w[issued updated corrected cancelled material_content_changed].freeze

  belongs_to :weather_alert_observation
  belongs_to :previous_observation, class_name: "WeatherAlertObservation", optional: true
  has_many :weather_alert_signal_resorts, dependent: :restrict_with_exception
  has_many :resorts, through: :weather_alert_signal_resorts

  validates :signal_type, inclusion: { in: TYPES }
  validates :detected_at, presence: true
  validates :weather_alert_observation_id, uniqueness: true

  def readonly?
    persisted?
  end
end
