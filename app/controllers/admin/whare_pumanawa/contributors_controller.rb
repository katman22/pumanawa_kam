class Admin::WharePumanawa::ContributorsController < Admin::WharePumanawa::BaseController
  before_action :set_contributor, only: [ :edit, :update ]

  def index
    @contributors = ::WharePumanawa::Contributor.ordered
  end

  def new
    @contributor = ::WharePumanawa::Contributor.new
  end

  def create
    @contributor = ::WharePumanawa::Contributor.new(contributor_params)
    if @contributor.save
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
  end

  def contributor_params
    params.require(:whare_pumanawa_contributor).permit(:name, :bio, :location, :position, :active)
  end
end
