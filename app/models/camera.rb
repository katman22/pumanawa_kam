class Camera < ApplicationRecord
  KINDS = %w[parking traffic].freeze
  belongs_to :resort

  validates :kind, inclusion: { in: KINDS }
  validates :name, presence: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }, allow_nil: true
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }, allow_nil: true
  validates :bearing, numericality: { greater_than_or_equal_to: 0, less_than: 360 }, allow_nil: true

  scope :with_coordinates, -> { where.not(latitude: nil, longitude: nil) }
  scope :parking, -> { where(kind: "parking") }
  scope :traffic, -> { where(kind: "traffic") }
  scope :visible, -> { where(show: true) }
  scope :featured_first, -> { order(featured: :desc, position: :asc, id: :asc) }
  scope :for_homepage, -> { visible.featured_first }

  def coordinates?
    latitude.present? && longitude.present?
  end

  # Consistent accessors for URLs stored in data
  def snapshot_url = data["snapshot_url"]

  def stream_url = data["stream_url"]

  def refresh_seconds = data["refresh_seconds"]
end
