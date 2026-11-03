class WeatherAlertSignalResort < ApplicationRecord
  belongs_to :weather_alert_signal
  belongs_to :resort

  validates :associated_at, presence: true
  validates :resort_id, uniqueness: { scope: :weather_alert_signal_id }
  validates :evidence, presence: true

  def readonly?
    persisted?
  end
end
