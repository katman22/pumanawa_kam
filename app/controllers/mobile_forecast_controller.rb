class MobileForecastController < ApplicationController
  
  FULL_TURBO = "full_response"
  
  def index

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

  def create_forecasts
    @location = params[:location]
    service_result = Noaa::Forecast::TextOnly.(params[:lat], params[:long])
    if service_result.success?
      @forecasts = service_result.value["forecasts"]
    else
      @erred = true
      @message = service_result.value
    end
  end

end
