class Admin::WharePumanawa::ProjectsController < Admin::WharePumanawa::BaseController
  before_action :set_project, only: [ :show, :edit, :update ]

  def index
    @projects = available_projects
  end

  def show
    @murals = @project.murals.ordered
    @memberships = @project.project_memberships.includes(:admin_user).order(:id)
    @eligible_admins = Admin::User.where(role: :mural_admin, active: true).where.not(id: @project.project_memberships.select(:admin_user_id)).order(:username)
  end

  def new
    @project = ::WharePumanawa::Project.new
  end

  def create
    @project = ::WharePumanawa::Project.new(project_params)
    saved = ::WharePumanawa::Project.transaction do
      if @project.save
        @project.project_memberships.create!(admin_user: current_admin_user) unless current_admin_user.super_admin?
        true
      else
        false
      end
    end
    if saved
      redirect_to admin_whare_pumanawa_project_path(@project), notice: "Project created.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @project.update(project_params)
      redirect_to admin_whare_pumanawa_project_path(@project), notice: "Project updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_project
    @project = ::WharePumanawa::Project.find(params[:id])
    require_project_access!(@project)
  end

  def project_params
    params.require(:whare_pumanawa_project).permit(:name, :description, :location, :position, :active)
  end
end
