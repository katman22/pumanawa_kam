class Admin::WharePumanawa::OrganizationMembershipsController < Admin::WharePumanawa::BaseController
  before_action :require_mahi_tahi_manager!
  before_action :set_organization

  def create
    admin = Admin::User.find_by(id: params.require(:organization_membership)[:admin_user_id], role: :organization_admin, active: true)
    membership = @organization.organization_memberships.new(admin_user: admin)
    if membership.save
      redirect_to admin_whare_pumanawa_organization_path(@organization), notice: "Organization admin added.", status: :see_other
    else
      redirect_to admin_whare_pumanawa_organization_path(@organization), alert: membership.errors.full_messages.join(", "), status: :see_other
    end
  end

  def destroy
    @organization.organization_memberships.find(params[:id]).destroy!
    redirect_to admin_whare_pumanawa_organization_path(@organization), notice: "Organization admin removed.", status: :see_other
  end

  private

  def set_organization
    @organization = ::WharePumanawa::Organization.find(params[:organization_id])
  end
end
