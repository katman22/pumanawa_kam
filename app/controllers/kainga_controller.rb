class KaingaController < ApplicationController
  def index
    @is_mobile = mobile_device?
  end
end
