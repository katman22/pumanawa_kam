class Admin::WeatherForecastObservationsController < Admin::BaseController
  before_action :require_canyon_admin!

  def show
    @resort = Resort.find(params[:resort_id])
    @observation = WeatherForecastObservation.where(resort_id: @resort.id).find(params[:id])
    @monitor = ResortWeatherMonitor.find_by(resort_id: @resort.id) || ResortWeatherMonitor.new(resort: @resort)
  end
end
