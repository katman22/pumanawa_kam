# frozen_string_literal: true
module Iap
  class Confirm < ApplicationService
    def initialize(user:, platform:, payload:)
      @user = user
      @platform = platform # "ios"|"android"
      @payload = payload   # raw purchase payload from client
    end

    def call
      normalized =
        case @platform
        when "ios"     then Iap::Apple::Verify.call!(payload: @payload).value
        when "android" then Iap::Google::Verify.call!(payload: @payload).value
        else
          return failed("Unsupported platform")
        end

      Iap::UpsertSubscription.call!(user: @user, attrs: normalized)
      Entitlements::Resolver.call!(user: @user)
    end
  end
end
