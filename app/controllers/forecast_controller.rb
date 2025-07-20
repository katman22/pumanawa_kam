class ForecastController < ApplicationController
  include BaseForecaster

  DEFAULT_LAYER = "precipitation"

  def index
    @erred, @locations, @total = find_locations(params[:location])
    return unless @locations&.size == 1
    locale = @locations.first
    location_context = location_ctx(locale.merge("lat" => locale["geometry"]["lat"], "lng" => locale["geometry"]["lng"]))
    @erred, @summary = summary_forecast_for_location(location_context.latitude, location_context.longitude)
  end

  def radar_for_locale_web
    @lat = params[:lat]
    @lng = params[:lng]
    @type = params[:type] || DEFAULT_LAYER
    render layout: "map_web", locals: { type: @type, lng: @lng, lat: @lat }
  end

  def radar_for_locale
    @lat = params[:lat]
    @lng = params[:lng]
    @type = params[:type] || DEFAULT_LAYER
    render layout: "map_only", locals: { type: @type, lng: @lng, lat: @lat }
  end

  def geo_location
    location = params[:location]
    erred, locations, total = location_services(location)
    multi_locations(locations: locations, total: total, erred: erred, location: location)
  end

  def summary
    location_context, _recent_locations = set_defaults
    erred, summary = summary_forecast_for_location(location_context.latitude, location_context.longitude)
    render partial: "forecast_summary", locals: { summary: summary, location: location_context.location, location_name: location_context.location_name, erred: erred }
  end

  def full
    @location_context, _recent_locations = set_defaults
    @erred, @forecasts = create_forecasts(latitude: @location_context.latitude, longitude: @location_context.longitude)
  end

  def dual_full
    location_context, _recent_locations = set_defaults
    erred, forecasts = create_forecasts(latitude: location_context.latitude, longitude: location_context.longitude)
    render_forecast(params[:turbo_location], forecasts, erred, location_context)
  end

  def text_only
    @location_context, _recent_locations = set_defaults
    @erred, @forecasts = create_forecasts(latitude: @location_context.latitude, longitude: @location_context.longitude)
  end

  def multi_locations(locations:, total:, erred:, location:)
    render turbo_stream: [
      turbo_stream.replace("summary_response", partial: "clear"),
      turbo_stream.replace("location_response", partial: "geo_location", locals: { location: location, locations: locations, total: total, erred: erred })
    ]
  end

  def dual
    @recent_locations = session[:recent_locations]
  end

  def dual_geo_location
    location = params[:location]
    erred, locations, total = location_services(location)
    turbo_location = params[:commit] == SCREEN_A ? "location_response_a" : "location_response_b"
    return full_forecast_for_location(turbo_location, locations.first) if total == 1
    dual_multi_locations(turbo_location, location, locations, total, erred)
  end

  def dual_multi_locations(turbo_location, location, locations, total, erred)
    render turbo_stream: [
      turbo_stream.replace(
        turbo_location, partial: "geo_location_dual",
        locals: { location: location, locations: locations, total: total, erred: erred, turbo_location: turbo_location })
    ]
  end

  def full_forecast_for_location(turbo_location, found_location)
    location_context = LocationContext.new(
      {
        lat: found_location["geometry"]["lat"],
        long: found_location["geometry"]["lng"],
        location: params[:location],
        location_name: found_location["formatted"]
      }
    )
    erred, forecasts = create_forecasts(latitude: location_context.latitude, longitude: location_context.longitude)
    render_forecast(turbo_location, forecasts, erred, location_context)
  end

  def render_forecast(turbo_location, forecasts, erred, location_context)
    render turbo_stream: [
      turbo_stream.replace(
        turbo_location, partial: "dual_full",
        locals: { forecasts: forecasts, erred: erred, turbo_location: turbo_location, location_context: location_context })
    ]
  end

  def location_ctx(location_data)
    LocationContext.new(
      { location: params[:location], location_name: location_data["formatted"], lat: location_data["lat"], long: location_data["lng"] }
    )
  end
end
