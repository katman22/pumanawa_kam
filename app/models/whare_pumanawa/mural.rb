class WharePumanawa::Mural < ApplicationRecord
  has_many :mural_photos, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :mural

  attr_readonly :slug

  scope :ordered, -> { order(:position, :id) }
  scope :published, -> { where(published: true) }

  before_validation :generate_slug, on: :create
  around_create :retry_slug_collision

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :published, inclusion: { in: [ true, false ] }
  validates_associated :mural_photos, if: :published?
  validate :published_mural_has_photo

  private

  def slug_base
    title.to_s.parameterize.presence || "mural"
  end

  def generate_slug
    return if slug.present?

    self.slug = slug_base
    suffix = 2
    while self.class.exists?(slug: slug)
      self.slug = "#{slug_base}-#{suffix}"
      suffix += 1
    end
  end

  def retry_slug_collision
    attempts = 0
    begin
      # The savepoint keeps a uniqueness race from aborting the caller's transaction.
      self.class.transaction(requires_new: true) { yield }
    rescue ActiveRecord::RecordNotUnique => error
      raise unless error.message.include?("index_whare_pumanawa_murals_on_slug") && attempts < 3

      attempts += 1
      self.slug = "#{slug_base}-#{SecureRandom.hex(4)}"
      retry
    end
  end

  def published_mural_has_photo
    if published? && mural_photos.reject(&:marked_for_destruction?).empty?
      errors.add(:mural_photos, "must include at least one photo before publication")
    end
  end
end
