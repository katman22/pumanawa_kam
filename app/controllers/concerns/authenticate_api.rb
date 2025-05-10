module AuthenticateApi
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_api_request!
  end

  def authenticate_api_request!
    token = request.headers["Authorization"]&.split(" ")&.last
    secret = ENV["JWT_SECRET"]
    begin
      decoded = JWT.decode(token, secret, true, algorithm: "HS256")
    rescue JWT::DecodeError => e
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end
end
