# app/models/resort.rb
class Resort < ApplicationRecord
  has_many :resort_filters, dependent: :destroy
  has_many :parking_profiles, dependent: :destroy

  accepts_nested_attributes_for :resort_filters, allow_destroy: true

  validates :resort_name, :slug, :latitude, :longitude, presence: true
  validates :slug, :resort_name, uniqueness: true

  # convenience getters
  def filter(kind)
    resort_filters.by_kind(kind).first
  end

  def filter_data(kind, default: {})
    filter(kind)&.data || default
  end
end
