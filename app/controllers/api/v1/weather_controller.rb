class Api::V1::WeatherController < Api::V1::ApiController
  def index
    _erred, locations, _total = location_services(params[:location])
    formatted_results = format_locations(locations)
    render json: formatted_results
  end

  def forecasts
    set_defaults
    location_context = LocationContext.new(params)
    _erred, forecasts = create_forecasts(latitude: location_context.latitude, longitude: location_context.longitude)
    render json: { forecasts: forecasts, forecast_locale: params[:name], lat: params[:lat], long: params[:long] }
  end

  def hourly
    _erred, periods = hourly_forecasts(latitude: params[:lat], longitude: params[:long])
    render json: { periods: periods }
  end

  def discussion
    result = forecast_discussion(latitude: params[:lat], longitude: params[:long])
    render json: { discussion: result[1].value }
  end

  def alerts
    _erred, alerts = alert_forecasts(latitude: params[:lat], longitude: params[:long])
    render json: { alerts: alerts.value["alerts"] }
  end

  def watches_fire_alerts
    _erred, watches_response = fire_watch_and_alerts(latitude: params[:lat], longitude: params[:long])
    render json:  watches_response.value
  end


  def period
    _erred, period_data = period_forecasts(latitude: params[:lat], longitude: params[:long], period: params[:period])
    render json: { period: period_data }
  end

  def radar
    _erred, radar = radar_for_locale(latitude: params[:lat], longitude: params[:long])
    render json: { radar: radar }
  end

  private

  def format_locations(locations)
    locations.map do |result|
      {
        name: result["formatted"],
        lat: result["geometry"]["lat"],
        lng: result["geometry"]["lng"]
      }
    end
  end
end
