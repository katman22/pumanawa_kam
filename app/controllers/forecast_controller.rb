class ForecastController < ApplicationController
  def index
    if params[:location]
      set_defaults
      @location = params[:location]
      location_services
    end
  end

  def geo_location
    @location = params[:location]
    location_services

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

  def text_only
    set_defaults
    create_forecasts
  end

  private

  def location_services
    location_service_result = OpenCage::GeoLocation::LocationFromInput.(@location)
    @erred = location_service_result.failure?
    if @erred
      @locations = location_service_result.value
      @total = 0
    else
      @locations = location_service_result.value[:locations]
      @total = location_service_result.value[:total]
    end
  end

  def summary_forecast_for_location
    service_result = Noaa::Forecast::Summary.(@latitude, @longitude, @zip)
    if service_result.failure?
      @erred = true
      @summary = service_result.value
    else
      @summary = service_result.value
    end
    @summary = service_result.value
  end

  def create_forecasts
    service_result = Noaa::Forecast::TextOnly.(@latitude, @longitude, @zip)
    if service_result.success?
      @forecasts = service_result.value["forecasts"]
    else
      @erred = true
      @message = service_result.value
    end
  end

  def set_defaults
    @latitude = params[:lat]
    @longitude = params[:long]
    @location = params[:location]
    @location_name = params[:location_name]
    @zip = params[:zip]
    @erred = false
  end
end
