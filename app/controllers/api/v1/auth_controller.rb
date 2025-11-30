# app/controllers/api/v1/auth_controller.rb
class Api::V1::AuthController < Api::V1::BaseMobileApiController
  def device
    public_id = params.dig(:auth, :user_id).presence || params[:user_id].presence

    user =
      if public_id
        User.find_by(public_id: public_id) || User.create!
      else
        User.create!
      end

    token = JwtToken.issue({ user_id: user.id })
    render json: { user_id: user.public_id, jwt: token }
  end
end
