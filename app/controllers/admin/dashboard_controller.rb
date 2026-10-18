class Admin::DashboardController < Admin::BaseController
  def index
    return unless current_admin_user.organization_admin?

    @organizations = current_admin_user.administrable_organizations.ordered
    @organization = @organizations.find_by(id: params[:organization_id]) if params[:organization_id].present?
    if params[:organization_id].present? && !@organization
      ::WharePumanawa::Organization.find(params[:organization_id])
      return head :forbidden
    end
    @organization ||= @organizations.first if @organizations.size == 1
  end
end
