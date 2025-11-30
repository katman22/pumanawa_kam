class Api::V1::BaseMobileApiController < ActionController::API
  # Force JSON on all unexpected errors in API
  rescue_from StandardError, with: :render_unexpected_error
  rescue_from ActionController::RoutingError, with: :render_not_found
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private

  def render_not_found
    render json: { error: "Not Found" }, status: :not_found
  end

  def render_unexpected_error(error)
    Rails.logger.error("❌ API Error: #{error.class} — #{error.message}")
    Rails.logger.error(error.backtrace.join("\n")) if Rails.env.development?
    render json: { error: "Server Error" }, status: :internal_server_error
  end
end
