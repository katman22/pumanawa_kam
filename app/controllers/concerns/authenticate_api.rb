module AuthenticateApi
  extend ActiveSupport::Concern

  included do
    # before_action :authenticate_api_request!
  end

  def authenticate_api_request!
    token = request.headers["Authorization"]&.split(" ")&.last
    secret = ENV.fetch("JWT_TOKEN")
    Rails.logger.info  "Here is the Token found #{token}"
    Rails.logger.info  "Here is the JWT found  #{secret}"
    # begin
    #   decoded = JWT.decode(token, secret, true, algorithm: "HS256")
    # rescue JWT::DecodeError => e
    #   render json: { error: "Unauthorized" }, status: :unauthorized
    # end
  end
end
