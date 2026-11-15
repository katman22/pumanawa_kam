class Api::V1::WeatherMonitorsController < Api::V1::MobileApiController
  def show
    response.headers["Cache-Control"] = "private, no-store"
    resort = Resort.find_by!(slug: params[:resort_id])
    access = WeatherMonitoring::MobileAccess.call(user: current_user, resort: resort)
    if access.failure?
      status = access.value[:code] == "account_inactive" ? :unauthorized : :service_unavailable
      return render json: { error: access.value[:code] }, status: status
    end
    return render json: { error: "Weather access required" }, status: :forbidden unless access.value[:allowed]

    result = WeatherMonitoring::MobileSummary.call(resort: resort)
    render json: result.value, status: result.success? ? :ok : :service_unavailable
  end
end
