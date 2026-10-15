class WharePumanawa::MuralPhoto < ApplicationRecord
  belongs_to :mural, inverse_of: :mural_photos
  # Keep production artwork off web disk without requiring bucket credentials at boot.
  has_one_attached :image, service: ->(_photo) {
    Rails.env.production? ? :mural_artwork : Rails.application.config.active_storage.service
  } do |attachable|
    attachable.variant :thumbnail, resize_to_fill: [ 240, 180 ]
    attachable.variant :hero, resize_to_limit: [ 1600, 1600 ]
  end

  before_destroy :protect_published_hero

  scope :ordered, -> { order(:position, :id) }

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :alt_text, :image, presence: true, if: -> { mural&.published? }
  validate :supported_image

  private

  def protect_published_hero
    return if destroyed_by_association

    mural.with_lock do
      if mural.published? && !mural.mural_photos.where.not(id: id).includes(image_attachment: :blob).any?(&:valid?)
        errors.add(:base, "Unpublish this mural before removing its last valid photo.")
        throw :abort
      end
    end
  end

  def supported_image
    return unless image.attached?

    unless %w[image/jpeg image/png image/webp].include?(image.blob.content_type)
      errors.add(:image, "must be a JPEG, PNG, or WebP photograph")
    end
    errors.add(:image, "must be 20 MB or smaller") if image.blob.byte_size > 20.megabytes
  end
end
