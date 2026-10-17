class WharePumanawa::ProjectMembership < ApplicationRecord
  belongs_to :project, inverse_of: :project_memberships
  belongs_to :admin_user, class_name: "Admin::User", inverse_of: :project_memberships

  validates :admin_user_id, uniqueness: { scope: :project_id }
  validate :eligible_admin_user

  private

  def eligible_admin_user
    if admin_user && !admin_user.mural_admin?
      errors.add(:admin_user, "must have the mural admin product role")
    end
  end
end
