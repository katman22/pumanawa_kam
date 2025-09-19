class Api::V1::IapController < Api::V1::ApiController
  # POST /api/v1/iap/confirm
  # { platform: "ios"|"android", payload: {...} }
  def confirm
    result = Iap::Confirm.call(user: current_user, platform: params[:platform], payload: params[:payload])
    if result.success?
      render json: result.value, status: :ok
    else
      render json: { error: result.value }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/iap/restore
  # { platform: "ios"|"android", receipts: [ {...}, ... ] }
  def restore
    result = Iap::Restore.call(user: current_user, platform: params[:platform], receipts: params[:receipts])
    if result.success?
      render json: result.value, status: :ok
    else
      render json: { error: result.value }, status: :unprocessable_entity
    end
  end
end
