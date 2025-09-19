class Webhooks::AppleController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    Webhooks::Apple::HandleNotification.call!(jwt: request.body.read)
    head :ok
  end
end
