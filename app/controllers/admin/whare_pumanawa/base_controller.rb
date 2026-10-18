class Admin::WharePumanawa::BaseController < Admin::BaseController
  before_action :require_mural_admin!

  private

  def require_mahi_tahi_manager!
    head :forbidden unless current_admin_user.can_manage_mahi_tahi?
  end

  def available_contributors
    current_admin_user.administrable_contributors.ordered
  end

  def require_organization_write!(organization)
    return true if current_admin_user.can_administer_organization?(organization)

    head :forbidden
    false
  end

  def available_organizations
    current_admin_user.administrable_organizations.ordered
  end

  def require_organization_access!(organization)
    return true if current_admin_user.can_view_organization?(organization)

    head :forbidden
    false
  end

  def available_projects
    current_admin_user.administrable_projects.ordered
  end

  def require_project_access!(project)
    return true if current_admin_user.can_administer_project?(project)

    head :forbidden
    false
  end

  def require_mural_access!(mural)
    return true if current_admin_user.can_administer_mural?(mural)

    head :forbidden
    false
  end
end
