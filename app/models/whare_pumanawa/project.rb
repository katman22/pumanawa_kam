class WharePumanawa::Project < ApplicationRecord
  # Optional for older writers during rollout; required in admin saves.
  belongs_to :organization, optional: true, inverse_of: :projects
  validates :organization, presence: true, if: -> { organization_id.present? }
  validates :organization, presence: true, on: :admin

  has_many :murals, class_name: "WharePumanawa::Mural", inverse_of: :project, dependent: :restrict_with_error

  has_many :project_memberships, dependent: :restrict_with_error, inverse_of: :project
  has_many :admin_users, through: :project_memberships

  attr_readonly :slug
  scope :ordered, -> { order(:position, :id) }
  scope :active, -> { where(active: true) }

  before_validation :generate_slug, on: :create
  around_create :retry_slug_collision

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :active, inclusion: { in: [ true, false ] }

  private

  def slug_base
    name.to_s.tr("_", " ").parameterize.presence || "project"
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
      raise unless error.message.include?("index_whare_pumanawa_projects_on_slug") && attempts < 3

      attempts += 1
      self.slug = "#{slug_base}-#{SecureRandom.hex(4)}"
      retry
    end
  end
end
