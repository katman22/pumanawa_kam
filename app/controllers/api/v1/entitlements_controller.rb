class Api::V1::EntitlementsController < Api::V1::MobileApiController
  def index
    eff = Entitlements::Resolver.call(user: current_user)

    render json: eff.value
  end
end
