# app/controllers/admin/resorts_controller.rb
class Admin::ResortsController < Admin::BaseController
  before_action :set_resort, only: [ :show, :edit, :update, :destroy ]

  def index
    @resorts = Resort.order(:resort_name)
  end

  def show
    @resort = Resort.find(params[:id])
    @parking_profile = ParkingProfile.find_by(resort_id: @resort.slug)
  end

  def new
    @resort = Resort.new
    ResortFilter::KINDS.first(2).each { |k| @resort.resort_filters.build(kind: k, data: {}) }
  end

  def edit
  end

  def create
    @resort = Resort.new(resort_params)
    if @resort.save
      redirect_to admin_resort_path(@resort), notice: "Resort created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @resort.update(resort_params)
      redirect_to admin_resort_path(@resort), notice: "Resort updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @resort.destroy
    redirect_to admin_resorts_path, notice: "Resort deleted."
  end

  private

  def set_resort
    @resort = Resort.find(params[:id])
  end

  def resort_params
    params.require(:resort).permit(
      :resort_name, :slug, :latitude, :longitude, :departure_point, :location, :live,
      resort_filters_attributes: [ :id, :kind, :data, :_destroy ]
    )
  end
end
