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
