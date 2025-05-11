class MobileForecastController < ApplicationController
  include BaseForecaster
  FULL_TURBO = "full_response"

  def index
    @erred, @locations, @total = find_locations(params[:location])
    return unless @locations.size == 1

    full_location(@locations)
  end

  def full
    location_context = LocationContext.new(params)
    erred, forecasts = create_forecasts(latitude: location_context.latitude, longitude: location_context.longitude)
    render partial: "full", locals: { location_name: location_context.location_name, erred: erred, forecasts: forecasts }
  end

  def geo_location
    erred, locations, total = location_services(params[:location])
    multi_locations(erred, locations, total)
  end

  private

  def full_location(locations)
    found_location = locations.first
    params.merge!(lat: found_location["geometry"]["lat"], long: found_location["geometry"]["lng"], location_name: found_location["formatted"])
    location_context = LocationContext.new(params)
    erred, forecasts = create_forecasts(latitude: location_context.latitude, longitude: location_context.longitude)
    render turbo_stream: turbo_stream.replace(FULL_TURBO, partial: "full", locals: { location_name: location_context.location_name, erred: erred, forecasts: forecasts })
  end

  def multi_locations(erred, locations, total)
    return full_location(locations) if locations.size == 1
    render turbo_stream: [
      turbo_stream.replace("summary_response", partial: "clear"),
      turbo_stream.replace("location_response", partial: "geo_location", locals: { location: params[:location], locations: locations, total: total, erred: erred })
    ]
  end
end
