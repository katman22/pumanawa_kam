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

  # convenience getters
  def filter(kind)
    resort_filters.by_kind(kind).first&.parsed_data
  end

  def filter_data(kind, default: {})
    filter(kind) || default
  end
end
