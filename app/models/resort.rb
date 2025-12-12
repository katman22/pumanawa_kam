# app/models/resort.rb
class Resort < ApplicationRecord
  has_many :resort_filters, dependent: :destroy
  has_many :parking_profiles, dependent: :destroy
  has_many :cameras, inverse_of: :resort, dependent: :destroy
  has_many :parking_cameras, -> { where(kind: "parking") }, class_name: "Camera"
  has_many :traffic_cameras, -> { where(kind: "traffic") }, class_name: "Camera"

  accepts_nested_attributes_for :resort_filters, allow_destroy: true

  scope :active, -> { where(live: true) }
  validates :resort_name, :slug, :latitude, :longitude, presence: true
  validates :slug, :resort_name, uniqueness: true

  RESORT_CORRIDORS = {
    alta: {
      corridor: "Little Cottonwood Canyon (SR-210)",
      bounds: { min_lat: 40.55, max_lat: 40.62, min_lng: -111.70, max_lng: -111.52 }
    },

    snowbird: {
      corridor: "Little Cottonwood Canyon (SR-210)",
      bounds: { min_lat: 40.55, max_lat: 40.62, min_lng: -111.70, max_lng: -111.52 }
    },

    brighton: {
      corridor: "Big Cottonwood Canyon (SR-190)",
      bounds: { min_lat: 40.55, max_lat: 40.70, min_lng: -111.75, max_lng: -111.50 }
    },

    solitude: {
      corridor: "Big Cottonwood Canyon (SR-190)",
      bounds: { min_lat: 40.55, max_lat: 40.70, min_lng: -111.75, max_lng: -111.50 }
    },

    snowbasin: {
      corridor: "Ogden Canyon / Trappers Loop",
      bounds: { min_lat: 41.15, max_lat: 41.35, min_lng: -111.95, max_lng: -111.65 }
    },

    nordic_valley: {
      corridor: "Ogden Canyon / Trappers Loop",
      bounds: { min_lat: 41.20, max_lat: 41.35, min_lng: -111.95, max_lng: -111.65 }
    },

    powder: {
      corridor: "Eden / Powder Mountain Road",
      bounds: { min_lat: 41.30, max_lat: 41.45, min_lng: -111.85, max_lng: -111.65 }
    },

    parkcity: {
      corridor: "Parleys Summit / SR-224",
      bounds: { min_lat: 40.55, max_lat: 40.80, min_lng: -111.60, max_lng: -111.35 }
    },

    sundance: {
      corridor: "Provo Canyon (US-189 / SR-92)",
      bounds: { min_lat: 40.20, max_lat: 40.40, min_lng: -111.75, max_lng: -111.55 }
    },

    cherry_peak: {
      corridor: "Logan Canyon (US-89)",
      bounds: { min_lat: 41.80, max_lat: 42.00, min_lng: -111.80, max_lng: -111.55 }
    },

    beaver: {
      corridor: "Logan Canyon (US-89)",
      bounds: { min_lat: 41.60, max_lat: 41.90, min_lng: -111.90, max_lng: -111.60 }
    },

    brianhead: {
      corridor: "SR-143",
      bounds: { min_lat: 37.65, max_lat: 37.85, min_lng: -112.95, max_lng: -112.75 }
    },

    eagle_point: {
      corridor: "SR-153",
      bounds: { min_lat: 38.20, max_lat: 38.45, min_lng: -112.60, max_lng: -112.35 }
    }
  }.freeze

  # convenience getters
  def filter(kind)
    resort_filters.by_kind(kind).first&.parsed_data
  end

  def filter_data(kind, default: {})
    filter(kind) || default
  end

  def snow_plow_bounds
    case slug
    when "brighton", "solitude"
      {
        min_lat: 40.55,
        max_lat: 40.75,
        min_lng: -111.75,
        max_lng: -111.45
      }
    when "alta", "snowbird"
      {
        min_lat: 40.55,
        max_lat: 40.75,
        min_lng: -111.70,
        max_lng: -111.45
      }
    else
      nil
    end
  end

end
