class Admin::User < ApplicationRecord
  self.table_name = "admin_users"

  has_many :project_memberships, class_name: "WharePumanawa::ProjectMembership", foreign_key: :admin_user_id, inverse_of: :admin_user, dependent: :destroy

  has_secure_password reset_token: false
  normalizes :username, with: ->(value) { value.strip.downcase }
  enum :role, { super_admin: "super_admin", canyon_admin: "canyon_admin", mural_admin: "mural_admin" }, validate: true

  before_update :protect_final_active_super_admin, if: -> { will_save_change_to_role? || will_save_change_to_active? }

  validates :username, presence: true, uniqueness: true
  validates :active, inclusion: { in: [ true, false ] }
  validates :password, length: { minimum: 12 }, allow_nil: true

  def can_administer_canyon?
    super_admin? || canyon_admin?
  end

  def can_administer_murals?
    super_admin? || mural_admin?
  end

  def administrable_projects
    projects = ::WharePumanawa::Project.all
    return projects.none unless active? && can_administer_murals?
    return projects if super_admin?

    projects.where(id: project_memberships.select(:project_id))
  end

  # Organization context is inferred; this never grants project membership.
  def administrable_organizations
    organizations = ::WharePumanawa::Organization.all
    return organizations.none unless active? && can_administer_murals?
    return organizations if super_admin?

    organizations.where(id: administrable_projects.where.not(organization_id: nil).select(:organization_id))
  end

  def can_view_organization?(organization)
    return false unless active? && can_administer_murals? && organization&.persisted?

    super_admin? || administrable_projects.exists?(organization_id: organization.id)
  end

  def administrable_murals
    murals = ::WharePumanawa::Mural.all
    return murals.none unless active? && can_administer_murals?
    return murals if super_admin?

    murals.where(project_id: administrable_projects.select(:id))
  end

  def can_administer_project?(project)
    return false unless active? && can_administer_murals?
    return false unless project&.persisted?

    super_admin? || project_memberships.exists?(project_id: project.id)
  end

  def can_administer_mural?(mural)
    mural.present? && active? && can_administer_murals? && (super_admin? || can_administer_project?(mural.project))
  end

  private

  def protect_final_active_super_admin
    # Serialize rare role/status changes, including edits to different admin rows.
    # The transaction lock is released automatically at commit/rollback.
    self.class.connection.execute("SELECT pg_advisory_xact_lock(20261015, 1)")
    persisted = self.class.find(id)
    resulting_role = will_save_change_to_role? ? role : persisted.role
    resulting_active = will_save_change_to_active? ? active : persisted.active
    return unless persisted.active? && persisted.super_admin?
    return if resulting_active && resulting_role == "super_admin"
    return if self.class.where(active: true, role: :super_admin).where.not(id: id).exists?

    errors.add(:base, "At least one active super admin must remain.")
    throw :abort
  end
end
