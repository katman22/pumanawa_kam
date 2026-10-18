class Admin::WharePumanawa::OrganizationContributorsController < Admin::WharePumanawa::BaseController
  before_action :require_super_admin!
  before_action :set_organization

  def create
    contributor = ::WharePumanawa::Contributor.find(params.require(:organization_contributor)[:contributor_id])
    association = @organization.organization_contributors.find_or_create_by!(contributor: contributor)
    redirect_to admin_whare_pumanawa_organization_path(association.organization), notice: "Contributor associated.", status: :see_other
  end

  def destroy
    @organization.organization_contributors.find(params[:id]).destroy!
    redirect_to admin_whare_pumanawa_organization_path(@organization), notice: "Contributor association removed.", status: :see_other
  end

  private

  def set_organization
    @organization = ::WharePumanawa::Organization.find(params[:organization_id])
  end
end
