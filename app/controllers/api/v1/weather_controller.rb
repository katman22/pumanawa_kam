class Api::V1::WeatherController < Api::V1::ApiController
  def index
    _erred, locations, _total = location_services(params[:location])
    render json: locations
  end

  def forecasts
    set_defaults
    @location_context = LocationContext.new(params)
    _erred, forecasts = forecaster
    render json: { forecasts: forecasts, forecast_locale: params[:name], lat: params[:lat], long: params[:long] }
  end

  def hourly
    @location_context = LocationContext.new(params)
    _erred, periods = hourly_forecaster
    render json: { periods: periods }
  end

  def discussion
    result = forecast_discussion(latitude: params[:lat], longitude: params[:long], country_code: params[:country_code])
    render json: { discussion: result[1].value }
  end

  def alerts
    _erred, alerts = create_alert_forecasts(latitude: params[:lat], longitude: params[:long], country_code: params[:country_code])
    render json: { alerts: alerts.value["alerts"] }
  end

  def watches_fire_alerts
    _erred, watches_response = fire_watch_and_alerts(latitude: params[:lat], longitude: params[:long], country_code: params[:country_code])
    render json:  watches_response.value
  end


  def period
    _erred, period_data = period_forecasts(latitude: params[:lat], longitude: params[:long], period: params[:period], country_code: params[:country_code])
    render json: { period: period_data }
  end

  def radar
    _erred, radar = radar_for_locale(latitude: params[:lat], longitude: params[:long])
    render json: { radar: radar }
  end

  private

  def forecaster
    results = create_forecasts(latitude: @location_context.latitude, longitude: @location_context.longitude, country_code: params[:country_code])
    forecasts = params[:country_code] == "us" ? results.last["forecasts"] : results.last
    [ results.first, forecasts ]
  end

  def hourly_forecaster
    results = create_hourly_forecasts(latitude: @location_context.latitude, longitude: @location_context.longitude, country_code: params[:country_code])
    periods = params[:country_code] == "us" ? results.last["periods"] : results.last
    [ results.first, periods ]
  end
end
