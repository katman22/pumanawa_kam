# frozen_string_literal: true

class LocationContext
  attr_reader :location, :location_name, :latitude, :longitude, :country_code

  def initialize(params)
    @location = params[:location]
    @location_name = params[:location_name]
    @latitude = params[:lat]
    @longitude = params[:long]
    @country_code = params[:country_code]
  end

  def to_h
    {
      location: location,
      location_name: location_name,
      latitude: latitude,
      longitude: longitude,
      country_code: country_code
    }
  end
end
