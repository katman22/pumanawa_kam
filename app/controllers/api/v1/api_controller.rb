class Api::V1::ApiController < ActionController::API
  include BaseForecaster
  include AuthenticateApi

  attr_accessor :formatted_results

  NOT_FOUND ="Not Found"

  # protect_from_forgery with: :null_session

  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: NOT_FOUND }, status: :not_found
  end
end
