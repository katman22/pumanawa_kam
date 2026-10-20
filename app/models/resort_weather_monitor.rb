class ResortWeatherMonitor < ApplicationRecord
  belongs_to :resort
  belongs_to :current_forecast_observation, class_name: "WeatherForecastObservation", optional: true

  validates :resort_id, uniqueness: true
  validates :provider, inclusion: { in: [ "noaa" ] }
  validates :enabled, inclusion: { in: [ true, false ] }
  validates :failure_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :observation_belongs_to_resort

  private

  def observation_belongs_to_resort
    if current_forecast_observation && current_forecast_observation.resort_id != resort_id
      errors.add(:current_forecast_observation, "must belong to this resort")
    end
  end
end
