class LocationContext
  attr_reader :location, :location_name, :latitude, :longitude

  def initialize(params)
    @location = params[:location]
    @location_name = params[:location_name]
    @latitude = params[:lat]
    @longitude = params[:long]
  end

  def to_h
    {
      location: location,
      location_name: location_name,
      latitude: latitude,
      longitude: longitude
    }
  end
end
