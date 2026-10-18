class WharePumanawa::OrganizationMembership < ApplicationRecord
  belongs_to :organization, inverse_of: :organization_memberships
  belongs_to :admin_user, class_name: "Admin::User", inverse_of: :organization_memberships

  validates :admin_user_id, uniqueness: { scope: :organization_id }
  validate :eligible_admin_user

  private

  def eligible_admin_user
    if admin_user && (!admin_user.organization_admin? || !admin_user.active?)
      errors.add(:admin_user, "must be an active organization admin")
    end
  end
end
