class Api::V1::WeatherController < Api::V1::ApiController
  def index
    _erred, locations, _total = location_services(params[:location])
    formatted_results = format_locations(locations)
    render json: formatted_results
  end

  def forecasts
    _erred, forecasts = create_forecasts(latitude: params[:lat], longitude: params[:long])
    render json: { forecasts: forecasts, forecast_locale: params[:name] }
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
