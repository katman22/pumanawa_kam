class Admin::User < ApplicationRecord
  self.table_name = "admin_users"

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
