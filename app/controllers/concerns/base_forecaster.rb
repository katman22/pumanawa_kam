module BaseForecaster
  extend ActiveSupport::Concern

  included do
    DUAL = "Dual Screen"
    SCREEN_A = "Locale A"
    SCREEN_B = "Locale B"

    def find_locations
      return unless params[:location]
      set_defaults
      @location = params[:location]
      location_services
    end

    def find_forecast
      return unless params[:location]
      set_defaults
      @location = params[:location]
      location_services
    end

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
      service_result = Noaa::Forecast::Summary.(params[:lat], params[:long])
      if service_result.failure?
        @erred = true
        @summary = service_result.value
      else
        @summary = service_result.value
      end
      @summary = service_result.value
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

    def set_defaults
      @location = params[:location]
      @location_name = params[:location_name]
      @erred = false
      @recent_locations = recent_locations
    end

    def recent_locations
      session[:recent_locations] = session[:recent_locations] || []
      session[:recent_locations].unshift(location_data)
      session[:recent_locations].uniq!
      session[:recent_locations] = session[:recent_locations].take(12)
    end

    def location_data
      { location: @location, location_name: @location_name, latitude: params[:lat], longitude: params[:long] }
    end
  end
end
