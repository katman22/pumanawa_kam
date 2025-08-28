class Admin::CamerasController < Admin::BaseController
  before_action :set_resort
  before_action :set_camera, only: [ :show, :edit, :update, :destroy ]

  def new
    @camera = @resort.cameras.new(kind: params[:kind])
    @camera.data ||= { source: "udot", snapshot_url: "", stream_url: "", location: "", milepost: nil, direction: "", refresh_seconds: 60 }
  end

  def index; end

  # GET /admin/resorts/:resort_id/cameras/:id
  def show; end

  # GET /admin/resorts/:resort_id/cameras/:id/edit
  def edit; end

  def create
    @camera = @resort.cameras.new(camera_params)
    assign_next_position(@camera)

    if @camera.save
      redirect_to edit_admin_resort_camera_path(@resort, @camera), notice: "Camera created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # DELETE /admin/resorts/:resort_id/cameras/:id
  def destroy
    @camera.destroy
    redirect_to admin_resort_cameras_path(@resort), notice: "Camera deleted."
  end

  def update
    saved = @camera.update(camera_params)
    return render :index, resort: @resort, flash: "Camera updated." if saved

    render :edit, status: :unprocessable_entity
  end

  private

  def camera_params
    # Permit data as string, then parse to Hash
    raw = params.require(:camera).permit(
      :name, :kind, :show, :featured, :position, :latitude, :longitude,
      :bearing, :road, :jurisdiction, :data
    )

    raw[:show] = ActiveModel::Type::Boolean.new.cast(raw[:show])
    raw[:featured] = ActiveModel::Type::Boolean.new.cast(raw[:featured])
    raw[:position] = raw[:position].presence
    raw[:latitude] = raw[:latitude].presence
    raw[:longitude] = raw[:longitude].presence
    raw[:bearing] = raw[:bearing].presence
    if raw[:data].is_a?(String)
      begin
        parsed = JSON.parse(raw[:data])
        raw[:data] = parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        raw[:data] = {}
      end
    end

    raw
  end

  def set_resort
    @resort = Resort.find(params[:resort_id])
  end

  def set_camera
    @camera = @resort.cameras.find(params[:id])
  end

  def assign_next_position(camera)
    return if camera.position.present?
    max = @resort.cameras.where(kind: camera.kind).maximum(:position)
    camera.position = max.to_i + 1
  end
end
