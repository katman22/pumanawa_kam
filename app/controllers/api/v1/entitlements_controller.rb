class Api::V1::EntitlementsController < Api::V1::MobileApiController
  def show
    payload = Entitlements::Resolver.call(user: current_user).value

    render json: payload.merge(user_id: current_user.public_id)
  end
end
