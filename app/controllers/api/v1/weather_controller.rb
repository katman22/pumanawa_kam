class Api::V1::WeatherController < Api::V1::ApiController

  attr_accessor :formatted_results

  def index
    location_services
    # create_forecasts
    format_locations
    render json: @formatted_results
  end

  def forecasts
    create_forecasts
    render json: {forecasts:@forecasts, forecast_locale: params[:name]}
  end

  def create_forecasts
    service_result = Noaa::Forecast::TextOnly.(params[:lat], params[:long])
    if service_result.success?
      @forecasts = service_result.value["forecasts"]
    else
      @erred = true
      @message = service_result.value
    end
  end

  def format_locations
    @formatted_results = @locations.map do |result|
      {
        name: result["formatted"],
        lat: result["geometry"]["lat"],
        lng: result["geometry"]["lng"]
      }
    end
  end

  def location_services
    location_service_result = OpenCage::GeoLocation::LocationFromInput.(params[:location])
    @erred = location_service_result.failure?
    if @erred
      @locations = location_service_result.value
      @total = 0
    else
      @locations = location_service_result.value[:locations]
      @total = location_service_result.value[:total]
    end
  end

end
