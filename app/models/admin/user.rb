class Admin::User < ApplicationRecord
  self.table_name = "admin_users"

  has_many :project_memberships, class_name: "WharePumanawa::ProjectMembership", foreign_key: :admin_user_id, inverse_of: :admin_user, dependent: :destroy
  has_many :organization_memberships, class_name: "WharePumanawa::OrganizationMembership", foreign_key: :admin_user_id, inverse_of: :admin_user, dependent: :destroy

  has_secure_password reset_token: false
  normalizes :username, with: ->(value) { value.strip.downcase }
  enum :role, { super_admin: "super_admin", canyon_admin: "canyon_admin", mural_admin: "mural_admin",
    mahi_tahi_admin: "mahi_tahi_admin", organization_admin: "organization_admin" }, validate: true

  before_update :protect_final_active_super_admin, if: -> { will_save_change_to_role? || will_save_change_to_active? }

  validates :username, presence: true, uniqueness: true
  validates :active, inclusion: { in: [ true, false ] }
  validates :password, length: { minimum: 12 }, allow_nil: true

  def can_administer_canyon?
    active? && (super_admin? || canyon_admin?)
  end

  def can_administer_murals?
    active? && (super_admin? || mural_admin? || mahi_tahi_admin? || organization_admin?)
  end

  def can_manage_mahi_tahi?
    active? && (super_admin? || mahi_tahi_admin?)
  end

  def administrable_projects
    projects = ::WharePumanawa::Project.all
    return projects.none unless active? && can_administer_murals?
    return projects if can_manage_mahi_tahi?
    return projects.where(organization_id: administrable_organizations.select(:id)) if organization_admin?

    projects.where(id: project_memberships.select(:project_id))
  end

  # Organization admins own workspace authority; project members only infer context.
  def administrable_organizations
    organizations = ::WharePumanawa::Organization.all
    return organizations.none unless active? && can_administer_murals?
    return organizations if can_manage_mahi_tahi?
    return organizations.where(id: organization_memberships.select(:organization_id)) if organization_admin?

    organizations.where(id: administrable_projects.where.not(organization_id: nil).select(:organization_id))
  end

  def can_view_organization?(organization)
    return false unless active? && can_administer_murals? && organization&.persisted?

    administrable_organizations.exists?(id: organization.id)
  end

  def can_administer_organization?(organization)
    can_view_organization?(organization) && (can_manage_mahi_tahi? || organization_admin?)
  end

  # Preserve legacy Contributor CRUD for project-scoped mural_admin accounts.
  # Organization admins receive an explicitly isolated Contributor workspace.
  def administrable_contributors
    contributors = ::WharePumanawa::Contributor.all
    return contributors.none unless can_administer_murals?
    return contributors unless organization_admin?

    contributors.where(id: ::WharePumanawa::OrganizationContributor.where(organization_id: administrable_organizations.select(:id)).select(:contributor_id))
  end

  def associable_contributors
    return ::WharePumanawa::Contributor.none unless can_administer_murals?
    return administrable_contributors unless organization_admin?

    public_contributors = ::WharePumanawa::Contributor.active.where(id: ::WharePumanawa::Mural.published.select(:contributor_id))
    administrable_contributors.or(public_contributors)
  end

  def can_administer_contributor?(contributor)
    return false unless contributor&.persisted? && administrable_contributors.exists?(id: contributor.id)
    return true unless organization_admin?

    owned = administrable_organizations.select(:id)
    return false if contributor.organization_contributors.where.not(organization_id: owned).exists?

    contributor.murals.where.not(id: administrable_murals.select(:id)).none?
  end

  def administrable_murals
    murals = ::WharePumanawa::Mural.all
    return murals.none unless active? && can_administer_murals?
    return murals if can_manage_mahi_tahi?

    murals.where(project_id: administrable_projects.select(:id))
  end

  def can_administer_project?(project)
    return false unless active? && can_administer_murals?
    return false unless project&.persisted?

    administrable_projects.exists?(id: project.id)
  end

  def can_administer_mural?(mural)
    mural.present? && active? && can_administer_murals? && (can_manage_mahi_tahi? || can_administer_project?(mural.project))
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
