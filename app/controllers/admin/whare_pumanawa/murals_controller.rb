class Admin::WharePumanawa::MuralsController < Admin::WharePumanawa::BaseController
  before_action :load_contributors, only: [ :new, :create, :edit, :update ]
  before_action :set_mural, only: [ :show, :edit, :update, :destroy ]

  def index
    @murals = ::WharePumanawa::Mural.ordered.includes(mural_photos: { image_attachment: :blob })
  end

  def new
    @mural = ::WharePumanawa::Mural.new
  end

  def create
    @mural = ::WharePumanawa::Mural.new(mural_params)
    if @mural.save
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
    saved = @mural.with_lock { @mural.update(mural_params) }
    if saved
      redirect_to edit_admin_whare_pumanawa_mural_path(@mural), notice: "Mural updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @mural.with_lock { @mural.destroy! }
    redirect_to admin_whare_pumanawa_murals_path, notice: "Mural deleted.", status: :see_other
  end

  private

  def set_mural
    @mural = ::WharePumanawa::Mural.includes(mural_photos: { image_attachment: :blob }).find(params[:id])
  end

  def load_contributors
    @contributors = ::WharePumanawa::Contributor.ordered
  end

  def mural_params
    params.require(:whare_pumanawa_mural).permit(:contributor_id, :title, :location, :year, :client, :description, :position, :published)
  end
end
