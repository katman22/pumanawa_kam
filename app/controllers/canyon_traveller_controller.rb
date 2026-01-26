class CanyonTravellerController < ApplicationController
  def index
    if mobile_device?
      render "mobile/index", layout: "mobile"
    else
      render "index"
    end
  end

  def support
  end

  def privacy
    render "privacy"
  end
end
