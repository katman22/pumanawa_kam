class MobileController < ApplicationController
  def index
    render "index", layout: "mobile"
  end
end
