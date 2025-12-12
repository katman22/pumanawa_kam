class KaingaController < ApplicationController
  def index
    return mobile if mobile_device?
    render "index"
  end

  def mobile
    render "mobile"
  end

  def privacy
    render "privacy"
  end

  def terms
    render "terms"
  end
end
