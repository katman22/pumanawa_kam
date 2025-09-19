class Webhooks::GoogleController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    raw = request.body.read.presence || "{}"
    Webhooks::Google::HandleRtdn.call!(raw: raw)
    head :ok
  end
end
