class Admin::WharePumanawa::ProjectsController < Admin::WharePumanawa::BaseController
  before_action :load_organizations, only: [ :new, :create, :edit, :update ]
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
    @project = ::WharePumanawa::Project.new(organization_id: params[:organization_id])
    require_organization_access!(@project.organization) if @project.organization_id.present?
  end

  def create
    @project = ::WharePumanawa::Project.new(project_params)
    return unless authorized_organization?

    saved = ::WharePumanawa::Project.transaction do
      if @project.save(context: [ :create, :admin ])
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
    saved = @project.with_lock do
      return unless require_project_access!(@project)

      attributes = project_params
      if !current_admin_user.super_admin? && attributes.key?(:organization_id) && attributes[:organization_id].to_s != @project.organization_id.to_s
        head :forbidden
        return
      end
      @project.assign_attributes(attributes)
      return unless authorized_organization?

      @project.save(context: [ :update, :admin ])
    end
    if saved
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

  def load_organizations
    @organizations = available_organizations
  end

  def authorized_organization?
    return true if @project.organization_id.blank?

    require_organization_access!(@project.organization)
  end

  def project_params
    params.require(:whare_pumanawa_project).permit(:organization_id, :name, :description, :location, :position, :active)
  end
end
