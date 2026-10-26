class Admin::WeatherMonitoringController < Admin::BaseController
  before_action :require_canyon_admin!
  before_action :set_monitor, except: :index
  before_action :require_brighton_pilot!, only: [ :enable, :disable, :evaluate, :probe ]

  HISTORY_LIMIT = 25
  SUMMARY_COLUMNS = %i[id resort_id source_updated_at first_fetched_at source_key forecast_window_start forecast_window_end content_sha256 normalization_version summary quality].freeze

  def index
    @monitors = ResortWeatherMonitor.includes(:resort).joins(:resort).order("resorts.resort_name", :id).to_a
    @observations = WeatherForecastObservation.select(*SUMMARY_COLUMNS)
      .where(id: @monitors.filter_map(&:current_forecast_observation_id)).index_by(&:id)
    @pilot_resort = Resort.find_by(slug: "brighton") unless @monitors.any? { |monitor| monitor.resort.slug == "brighton" }
  end

  def show
    @observation = @monitor.current_forecast_observation
    @history = WeatherForecastObservation.select(*SUMMARY_COLUMNS).where(resort_id: @resort.id)
      .order(first_fetched_at: :desc, id: :desc).limit(HISTORY_LIMIT)
    @zone_ids = Array(@monitor.mapping["forecastZone"]).filter_map { |url| url.to_s.split("/").last.presence }
    @alerts = @zone_ids.reduce(WeatherAlertObservation.none) do |scope, zone|
      scope.or(WeatherAlertObservation.where("affected_zone_ids @> ?::jsonb", [ zone ].to_json))
    end.order(source_sent_at: :desc, id: :desc).limit(HISTORY_LIMIT)
  end

  def enable
    change_enabled(true)
  end

  def disable
    change_enabled(false)
  end

  def evaluate
    run_evaluation(probe: false)
  end

  def probe
    run_evaluation(probe: true)
  end

  private

  def set_monitor
    @resort = Resort.find(params[:id])
    @monitor = ResortWeatherMonitor.includes(:current_forecast_observation).find_by(resort_id: @resort.id) || ResortWeatherMonitor.new(resort: @resort)
  end

  def require_brighton_pilot!
    head :forbidden unless @resort.slug == "brighton"
  end

  def change_enabled(value)
    if @monitor.update(enabled: value)
      redirect_to admin_weather_monitoring_resort_path(@resort), notice: "Brighton monitoring #{value ? 'enabled' : 'disabled'}.", status: :see_other
    else
      redirect_to admin_weather_monitoring_resort_path(@resort), alert: "Monitor could not be changed. Refresh and try again.", status: :see_other
    end
  rescue ActiveRecord::StaleObjectError
    redirect_to admin_weather_monitoring_resort_path(@resort), alert: "Monitor changed during this request. Refresh and try again.", status: :see_other
  end

  def run_evaluation(probe:)
    result = ::WeatherMonitoring::RunEvaluation.call(resort: @resort, persist: true, probe: probe)
    if result.success?
      redirect_to admin_weather_monitoring_resort_path(@resort), notice: "#{probe ? 'Discovery probe' : 'Detailed evaluation'} completed. Review the stored decision below.", status: :see_other
    else
      code = result.value.is_a?(Hash) ? result.value[:code] : nil
      redirect_to admin_weather_monitoring_resort_path(@resort), alert: "#{probe ? 'Discovery probe' : 'Evaluation'} failed: #{code.presence || 'see monitor diagnostics'}.", status: :see_other
    end
  end
end
