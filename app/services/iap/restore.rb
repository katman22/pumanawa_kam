# frozen_string_literal: true
module Iap
  class Restore < ApplicationService
    def initialize(user:, platform:, receipts:)
      @user = user
      @platform = platform # "ios"|"android"
      @receipts = receipts || [] # array of tokens/transactions
    end

    def call
      @receipts.each do |r|
        normalized =
          case @platform
          when "ios"     then Iap::Apple::Verify.call!(payload: r).value
          when "android" then Iap::Google::Verify.call!(payload: r).value
          end
        Iap::UpsertSubscription.call!(user: @user, attrs: normalized)
      end
      Entitlements::Resolver.call!(user: @user)
    end
  end
end
