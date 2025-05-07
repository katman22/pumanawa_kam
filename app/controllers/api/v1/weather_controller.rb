class Api::V1::WeatherController < Api::V1::ApiController
  include BaseForecaster
  attr_accessor :formatted_results

  def index
    location_services
    format_locations
    render json: @formatted_results
  end

  def forecasts
    create_forecasts
    render json: { forecasts: @forecasts, forecast_locale: params[:name] }
  end

  private

  def format_locations
    @formatted_results = @locations.map do |result|
      {
        name: result["formatted"],
        lat: result["geometry"]["lat"],
        lng: result["geometry"]["lng"]
      }
    end
  end
end
