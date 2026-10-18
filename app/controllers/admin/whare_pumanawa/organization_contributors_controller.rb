class Admin::WharePumanawa::OrganizationContributorsController < Admin::WharePumanawa::BaseController
  before_action :set_organization

  def create
    contributor = ::WharePumanawa::Contributor.find(params.require(:organization_contributor)[:contributor_id])
    return head :forbidden unless current_admin_user.associable_contributors.exists?(id: contributor.id)

    association = @organization.organization_contributors.find_or_create_by!(contributor: contributor)
    redirect_to admin_whare_pumanawa_organization_path(association.organization), notice: "Contributor associated.", status: :see_other
  end

  def destroy
    association = ::WharePumanawa::OrganizationContributor.find(params[:id])
    if association.organization_id != @organization.id
      return head(current_admin_user.can_administer_organization?(association.organization) ? :not_found : :forbidden)
    end
    association.destroy!
    redirect_to admin_whare_pumanawa_organization_path(@organization), notice: "Contributor association removed.", status: :see_other
  end

  private

  def set_organization
    @organization = ::WharePumanawa::Organization.find(params[:organization_id])
    require_organization_write!(@organization)
  end
end
