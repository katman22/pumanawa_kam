# frozen_string_literal: true

class ResortContext
  attr_reader :resort_name, :departure_point, :latitude, :longitude, :location

  def initialize(params)
    @resort_name = params[:resort_name]
    @departure_point = params[:departure_point]
    @latitude = params[:latitude]
    @longitude = params[:longitude]
    @location = params[:location]
  end

  def self.for(resort_id)
    resort_id = resort_id.to_s.strip.downcase
    return send(resort_id) if respond_to?(resort_id)

    self.default
  end

  def self.default
    brighton
  end

  def to_h
    {
      resort_name: resort_name,
      departure_point: departure_point,
      latitude: latitude,
      longitude: longitude,
      location: location
    }
  end

  def self.brighton
    self.new({
               resort_name: "Brighton Resort",
               latitude: 40.5986,
               longitude: -111.5845,
               departure_point: "Big Cottonwood Canyon Park",
               location: "Brighton Resort, Brighton, Utah"
             })
  end

  def self.solitude
    self.new({
               resort_name: "Solitude Mountain Resort",
               latitude: 40.624079,
               longitude: -111.5977,
               departure_point: "Big Cottonwood Canyon Park",
               location: "Solitude Entrance Rd, Brighton, Utah"
             })
  end

  def self.alta
    self.new({
               resort_name: "Alta",
               latitude: 40.589034,
               longitude: -111.638856,
               departure_point: "Little Cottonwood Parking Lot",
               location: "Alta, Utah"
             })
  end

  def self.snowbird
    self.new({
               resort_name: "Snowbird",
               latitude: 40.581098,
               longitude: -111.656624,
               departure_point: "Little Cottonwood Parking Lot",
               location: "9499 Bypass Rd, Sandy, UT 84092"
             })
  end
end
