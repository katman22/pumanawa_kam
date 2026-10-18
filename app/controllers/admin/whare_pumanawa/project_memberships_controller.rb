class Admin::WharePumanawa::ProjectMembershipsController < Admin::WharePumanawa::BaseController
  before_action :require_mahi_tahi_manager!
  before_action :set_project

  def create
    admin = Admin::User.find_by(id: params.require(:project_membership)[:admin_user_id], role: :mural_admin, active: true)
    membership = @project.project_memberships.new(admin_user: admin)
    if membership.save
      redirect_to admin_whare_pumanawa_project_path(@project), notice: "Project member added.", status: :see_other
    else
      redirect_to admin_whare_pumanawa_project_path(@project), alert: membership.errors.full_messages.join(", "), status: :see_other
    end
  end

  def destroy
    @project.project_memberships.find(params[:id]).destroy!
    redirect_to admin_whare_pumanawa_project_path(@project), notice: "Project member removed.", status: :see_other
  end

  private

  def set_project
    @project = ::WharePumanawa::Project.find(params[:project_id])
  end
end
