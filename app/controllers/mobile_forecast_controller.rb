class MobileForecastController < ApplicationController
  include BaseForecaster
  FULL_TURBO = "full_response"

  def index
    find_locations
  end

  def full
    create_forecasts
    @location_name = params[:location_name]
    render partial: "full", locals: { location: @location, locations: @locations, total: @total, erred: @erred }
  end

  def full_location
    found_location = @locations.first
    params.merge!(lat: found_location["geometry"]["lat"], long: found_location["geometry"]["lng"])
    @location_name = found_location["formatted"]
    create_forecasts
    render turbo_stream: turbo_stream.replace(FULL_TURBO, partial: "full", locals: { location: @location, locations: @locations, total: @total, erred: @erred })
  end

  def geo_location
    @location = params[:location]
    location_services
    multi_locations
  end

  def multi_locations
    return full_location if @locations.size == 1
    render turbo_stream: [
      turbo_stream.replace("summary_response", partial: "clear"),
      turbo_stream.replace("location_response", partial: "geo_location", locals: { location: @location, locations: @locations, total: @total, erred: @erred })
    ]
  end
end
