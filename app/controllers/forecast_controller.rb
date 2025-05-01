class ForecastController < ApplicationController
  include BaseForecaster

  def index
    find_locations
    find_forecast
  end

  def geo_location
    @location = params[:location]
    location_services
    multi_locations
  end

  def multi_locations
    render turbo_stream: [
      turbo_stream.replace("summary_response", partial: "clear"),
      turbo_stream.replace("location_response", partial: "geo_location", locals: { location: @location, locations: @locations, total: @total, erred: @erred })
    ]
  end

  def summary
    set_defaults
    summary_forecast_for_location
    render partial: "forecast_summary", locals: { summary: @summary, location: @location, zip: @zip, location_name: @location_name, erred: @erred }
  end

  def full
    set_defaults
    create_forecasts
  end

  def dual
    @recent_locations = session[:recent_locations]
  end

  def dual_geo_location
    @location = params[:location]
    location_services
    turbo_location = params[:commit] == SCREEN_A ? "location_response_a" : "location_response_b"
    return full_forecast_for_location(turbo_location) if @locations.size == 1
    dual_multi_locations(turbo_location)
  end

  def dual_multi_locations(turbo_location)
    render turbo_stream: [
      turbo_stream.replace(turbo_location, partial: "geo_location_dual", locals: { location: @location, locations: @locations, total: @total, erred: @erred, turbo_location: turbo_location })
    ]
  end

  def full_forecast_for_location(turbo_location)
    found_location = @locations.first
    @latitude = found_location["geometry"]["lat"]
    @longitude = found_location["geometry"]["lng"]
    @location = params[:location]
    @location_name = found_location["formatted"]
    @erred = false
    recent_locations
    create_forecasts
    render_forecast(turbo_location)
  end

  def render_forecast(turbo_location)
    render turbo_stream: [
      turbo_stream.replace(turbo_location, partial: "dual_full", locals: { forecasts: @forecasts, message: @message, erred: @erred, turbo_location: turbo_location })
    ]
  end

  def dual_full
    set_defaults
    create_forecasts
    render_forecast(params[:turbo_location])
  end

  def text_only
    set_defaults
    create_forecasts
  end
end
