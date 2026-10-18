class Admin::WharePumanawa::OrganizationsController < Admin::WharePumanawa::BaseController
  before_action :require_mahi_tahi_manager!, only: [ :new, :create ]
  before_action :set_organization, only: [ :show, :edit, :update ]
  before_action -> { require_organization_write!(@organization) }, only: [ :edit, :update ]

  def index
    @organizations = available_organizations
  end

  def show
    @projects = available_projects.where(organization_id: @organization.id)
    @associations = @organization.organization_contributors.includes(:contributor).order(:id)
    if current_admin_user.can_administer_organization?(@organization)
      @contributors = current_admin_user.associable_contributors.ordered.where.not(id: @organization.organization_contributors.select(:contributor_id))
    end
    if current_admin_user.can_manage_mahi_tahi?
      @memberships = @organization.organization_memberships.includes(:admin_user).order(:id)
      @eligible_admins = Admin::User.where(role: :organization_admin, active: true).where.not(id: @memberships.select(:admin_user_id)).order(:username)
    end
  end

  def new
    @organization = ::WharePumanawa::Organization.new
  end

  def create
    @organization = ::WharePumanawa::Organization.new(organization_params)
    if @organization.save
      redirect_to admin_whare_pumanawa_organization_path(@organization), notice: "Organization created.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @organization.update(organization_params)
      redirect_to admin_whare_pumanawa_organization_path(@organization), notice: "Organization updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_organization
    @organization = ::WharePumanawa::Organization.find(params[:id])
    require_organization_access!(@organization)
  end

  def organization_params
    params.require(:whare_pumanawa_organization).permit(:name, :description, :location, :position, :active)
  end
end
