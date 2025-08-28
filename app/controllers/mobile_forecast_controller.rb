class MobileForecastController < ApplicationController
  include BaseForecaster
  FULL_TURBO = "full_response"

  def index
    @erred, locations, @total = find_locations(params[:location])
    @locations = format_locations(locations)
    return unless @locations.size == 1
    locale = @locations.first
    @erred, @summary = summary_forecast_for_location(locale[:lat], locale[:lng])
  end

  def full
    @location_context = LocationContext.new(params)
    erred, forecasts = forecaster
    render partial: "full", locals: { location_name: @location_context.location_name, erred: erred, forecasts: forecasts }
  end

  def weather_map
    @lat = params[:lat]
    @lng = params[:lng]
    @type = params[:type] || DEFAULT_LAYER
    render layout: "map_web", locals: { lat: @lat, lng: @lng, type: @type }
  end

  def geo_location
    location = params[:location]
    erred, locations, total = location_services(location)
    multi_locations(locations: format_locations(locations), total: total, erred: erred, location: location)
  end

  private

  def forecaster
    results = create_forecasts(latitude: @location_context.latitude, longitude: @location_context.longitude, country_code: params[:country_code])
    forecasts = params[:country_code] == "us" ? results.last["forecasts"] : results.last
    [ results.first, forecasts ]
  end

  def format_locations(locations)
    Convert::Geolocation::Google.new(raw_data: locations).call
  end
end
