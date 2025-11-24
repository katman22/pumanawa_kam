# app/controllers/concerns/authenticate_mobile_api.rb
module AuthenticateMobileApi
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_api_request!
    attr_reader :current_user
  end

  def authenticate_api_request!
    token = request.headers["Authorization"]&.split(" ")&.last
    return unauthorized! if token.blank?
    begin
      payload = JwtToken.decode(token)
      @current_user = User.find(payload[:user_id])
    rescue => _
      unauthorized!
    end
  end

  def unauthorized!
    render json: { error: "Unauthorized" }, status: :unauthorized
  end
end
