# frozen_string_literal: true

class ResortContext
  attr_reader :resort_name, :departure_point, :latitude, :longitude, :location, :roadway_filter, :event, :alerts, :camera

  def initialize(params)
    @resort_name = params[:resort_name]
    @departure_point = params[:departure_point]
    @latitude = params[:latitude]
    @longitude = params[:longitude]
    @location = params[:location]
    @roadway_filter = params[:roadway_filter]
    @event = params[:event]
    @alerts = params[:alerts]
    @camera = params[:camera]
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
      location: location,
      roadway_filter: roadway_filter,
      event: event,
      alerts: alerts,
      camera: camera
    }
  end

  def self.brighton
    self.new({
               resort_name: "Brighton Resort",
               latitude: 40.5986,
               longitude: -111.5845,
               departure_point: "Big Cottonwood Canyon Park",
               location: "Brighton Resort, Brighton, Utah",
               roadway_filter: { "RoadwayName" => "SR-190" },
               event: { "RoadwayName" => "SR 190" },
               camera: { "Roadway" => "SR 190" },
               alerts: { "Regions" => "Region 2" }
             })
  end

  def self.solitude
    self.new({
               resort_name: "Solitude Mountain Resort",
               latitude: 40.624079,
               longitude: -111.5977,
               departure_point: "Big Cottonwood Canyon Park",
               location: "Solitude Entrance Rd, Brighton, Utah",
               roadway_filter: { "RoadwayName" => "SR-190" },
               event: { "RoadwayName" => "SR 190" },
               camera: { "Roadway" => "SR 190" },
               alerts: { "Regions" => "Region 2" }
             })
  end

  def self.alta
    self.new({
               resort_name: "Alta",
               latitude: 40.6757,
               longitude: -111.52115,
               departure_point: "Little Cottonwood Parking Lot",
               location: "Alta, Utah",
               roadway_filter: { "RoadwayName" => "SR-210" },
               event: { "RoadwayName" => "SR 210" },
               camera: { "Roadway" => "SR 210" },
               alerts: { "Regions" => "Region 2" }
             })
  end

  def self.snowbird
    self.new({
               resort_name: "Snowbird",
               latitude: 40.581098,
               longitude: -111.656624,
               departure_point: "Little Cottonwood Parking Lot",
               location: "9499 Bypass Rd, Sandy, UT 84092",
               roadway_filter: { "RoadwayName" => "SR-210" },
               camera: { "Roadway" => "SR 210" },
               event: { "RoadwayName" => "SR 210" },
               alerts: { "Regions" => "Region 2" }
             })
  end
end
