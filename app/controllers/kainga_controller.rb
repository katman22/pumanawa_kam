class KaingaController < ApplicationController
  def index
    return mobile unless mobile_device?
    render "index"
  end

  def mobile
    render "mobile"
  end
end
