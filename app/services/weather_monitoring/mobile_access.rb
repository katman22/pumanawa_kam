# frozen_string_literal: true

module WeatherMonitoring
  # Same full-weather boundary as the existing mobile Weather screen.
  class MobileAccess < ApplicationService
    def initialize(user:, resort:)
      @user, @resort = user, resort
    end

    def call
      return failed(code: "account_inactive") unless @user.status == "active" && @user.deleted_at.nil?

      entitlement = Entitlements::Resolver.call(user: @user)
      return failed(code: "entitlements_unavailable") if entitlement.failure?

      allowed = entitlement.value[:tier].to_s == "premium" ||
        HomeResort.for_user(@user).subscribed_only.exists?(resort_id: @resort.id)
      successful(allowed: allowed)
    rescue ActiveRecord::ActiveRecordError
      failed(code: "entitlements_unavailable")
    end
  end
end
