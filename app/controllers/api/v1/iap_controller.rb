class Api::V1::IapController < Api::V1::MobileApiController
  def sync
    entitlements = params.fetch(:entitlements, {})

    # Normalize & save products
    Iap::RevenueCat::SyncPurchases.new(user: current_user, entitlements: entitlements).call
    # save_store_subscriptions!(current_user, entitlements)

    # Recompute current effective entitlements
    result = Entitlements::Resolver.new(user: current_user).call

    render json: { status: "ok", entitlements: result.value }, status: :ok
  end

  private
end
