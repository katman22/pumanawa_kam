# app/controllers/admin/resort_filters_controller.rb
class Admin::ResortFiltersController < Admin::BaseController
  before_action :set_resort_filter, only: [ :edit, :update, :destroy ]
  before_action :set_parent, only: [ :new, :create ]

  def new
    @resort_filter = @resort.resort_filters.new(kind: params[:kind])
  end

  def create
    @resort_filter = @resort.resort_filters.new(resort_filter_params)
    if @resort_filter.save
      redirect_to admin_resort_path(@resort), notice: "Filter created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @resort_filter.update(resort_filter_params)
      redirect_to admin_resort_path(@resort_filter.resort), notice: "Filter updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    resort = @resort_filter.resort
    @resort_filter.destroy
    redirect_to admin_resort_path(resort), notice: "Filter deleted."
  end

  private

  def set_parent
    @resort = Resort.find(params[:resort_id])
  end

  def set_resort_filter
    @resort_filter = ResortFilter.find(params[:id])
  end

  def resort_filter_params
    params.require(:resort_filter).permit(:kind, :data)
  end
end
