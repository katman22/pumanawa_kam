# app/controllers/admin/parking_profiles_controller.rb
class Admin::ParkingProfilesController < Admin::BaseController
  def edit
    @resort = Resort.find_by!(id: params[:resort_id])
    @profile = ParkingProfile.find_by!(resort: @resort, season: params[:season])
  end

  def create
    service_response = Resorts::ParkingProfiles::Create.new(resort_id: params[:resort_id], season: params[:season]).call
    return redirect_to admin_edit_parking_profile_path(
                         resort_id: service_response.value.resort_id,
                         season: service_response.value.season) if service_response.success

    render :new, status: 422
  end

  def update
    filtered_params = profile_params.to_h
    service_response = Resorts::ParkingProfiles::Update.new(resort_id: params[:resort_id], params: filtered_params).call
    return redirect_to admin_edit_parking_profile_path(
                         resort_id: service_response.value.resort_id,
                         season: service_response.value.season),
                       notice: "Updated." if service_response.success
    binding.pry
    @profile = ParkingProfile.find_by!(resort: @resort, season: params[:season])
    flash.now[:alert] = "Error updating parking profile.#{service_response.value}"
    render :edit, status: :conflict
  end

  def show
    @resort = Resort.find_by!(id: params[:resort_id])
    @profile = ParkingProfile.find_by!(resort: @resort, season: params[:season])
  end

  private

  def profile_params
    params.require(:parking_profile).permit(
      :label, :season, :effective_from, :effective_to, :summary_markdown, :overnight, :lock_version,
      :operations, :highway_parking, :links, :sources, :rules, :faqs, :accessibility, :media, :live
    )
  end
end
