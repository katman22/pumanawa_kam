class Admin::WharePumanawa::ContributorsController < Admin::WharePumanawa::BaseController
  before_action :set_contributor, only: [ :edit, :update ]
  before_action :load_organizations, only: [ :new, :create ]

  def index
    @contributors = available_contributors
    if params[:organization_id].present?
      organization = ::WharePumanawa::Organization.find(params[:organization_id])
      return unless require_organization_access!(organization)

      @contributors = @contributors.where(id: organization.organization_contributors.select(:contributor_id))
    end
  end

  def new
    @contributor = ::WharePumanawa::Contributor.new
    @organization_id = params[:organization_id]
    if current_admin_user.organization_admin? && @organization_id.present?
      require_organization_write!(::WharePumanawa::Organization.find(@organization_id))
    end
  end

  def create
    @contributor = ::WharePumanawa::Contributor.new(contributor_params)
    @organization_id = params[:organization_id]
    if current_admin_user.organization_admin?
      organization = ::WharePumanawa::Organization.find_by(id: @organization_id)
      return head(:not_found) if @organization_id.present? && !organization
      return head(:forbidden) unless current_admin_user.can_administer_organization?(organization)
    end
    saved = ::WharePumanawa::Contributor.transaction do
      if @contributor.save
        organization.organization_contributors.create!(contributor: @contributor) if current_admin_user.organization_admin?
        true
      end
    end
    if saved
      redirect_to admin_whare_pumanawa_contributors_path, notice: "Contributor created.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @contributor.update(contributor_params)
      redirect_to admin_whare_pumanawa_contributors_path, notice: "Contributor updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_contributor
    @contributor = ::WharePumanawa::Contributor.find(params[:id])
    head :forbidden unless current_admin_user.can_administer_contributor?(@contributor)
  end

  def load_organizations
    @organizations = available_organizations if current_admin_user.organization_admin?
  end

  def contributor_params
    params.require(:whare_pumanawa_contributor).permit(:name, :bio, :location, :position, :active)
  end
end
