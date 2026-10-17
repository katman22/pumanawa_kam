class Admin::WharePumanawa::MuralsController < Admin::WharePumanawa::BaseController
  before_action :load_projects, only: [ :new, :create, :edit, :update ]
  before_action :load_contributors, only: [ :new, :create, :edit, :update ]
  before_action :set_mural, only: [ :show, :edit, :update, :destroy ]

  def index
    @murals = current_admin_user.administrable_murals.ordered.includes(:project, mural_photos: { image_attachment: :blob })
  end

  def new
    @mural = ::WharePumanawa::Mural.new(project_id: params[:project_id])
    require_project_access!(@mural.project) if @mural.project_id.present?
  end

  def create
    @mural = ::WharePumanawa::Mural.new(mural_params)
    return unless authorized_assignment?

    if @mural.save(context: [ :create, :admin ])
      redirect_to edit_admin_whare_pumanawa_mural_path(@mural), notice: "Mural created. Add photos below.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    redirect_to edit_admin_whare_pumanawa_mural_path(@mural)
  end

  def edit
  end

  def update
    saved = @mural.with_lock do
      return unless require_mural_access!(@mural)

      @mural.assign_attributes(mural_params)
      return unless authorized_assignment?

      @mural.save(context: [ :update, :admin ])
    end
    if saved
      redirect_to edit_admin_whare_pumanawa_mural_path(@mural), notice: "Mural updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @mural.with_lock do
      return unless require_mural_access!(@mural)

      @mural.destroy!
    end
    redirect_to admin_whare_pumanawa_murals_path, notice: "Mural deleted.", status: :see_other
  end

  private

  def set_mural
    @mural = ::WharePumanawa::Mural.includes(:project, mural_photos: { image_attachment: :blob }).find(params[:id])
    require_mural_access!(@mural)
  end

  def authorized_assignment?
    return true if @mural.project_id.blank?

    require_project_access!(@mural.project)
  end

  def load_projects
    @projects = available_projects
  end

  def load_contributors
    @contributors = ::WharePumanawa::Contributor.ordered
  end

  def mural_params
    params.require(:whare_pumanawa_mural).permit(:project_id, :contributor_id, :title, :location, :year, :client, :description, :position, :published)
  end
end
