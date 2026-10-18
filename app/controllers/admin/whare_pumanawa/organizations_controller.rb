class Admin::WharePumanawa::OrganizationsController < Admin::WharePumanawa::BaseController
  before_action :require_super_admin!, only: [ :new, :create, :edit, :update ]
  before_action :set_organization, only: [ :show, :edit, :update ]

  def index
    @organizations = available_organizations
  end

  def show
    @projects = available_projects.where(organization_id: @organization.id)
    @associations = @organization.organization_contributors.includes(:contributor).order(:id)
    @contributors = ::WharePumanawa::Contributor.ordered.where.not(id: @organization.organization_contributors.select(:contributor_id)) if current_admin_user.super_admin?
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
