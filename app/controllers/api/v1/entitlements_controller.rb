class Api::V1::EntitlementsController < Api::V1::ApiController
  def show
    render json: Entitlements::Resolver.call!(user: current_user).value
  end
end
