class Admin::BaseController < ApplicationController
  layout "admin"
  before_action :authenticate_admin
  helper_method :current_admin_user

  private

  def current_admin_user
    @current_admin_user ||= Admin::User.find_by(id: session[:admin_user_id], active: true)
  end

  def authenticate_admin
    response.headers["Cache-Control"] = "no-store"
    return if current_admin_user

    reset_session
    redirect_to admin_login_path
  end
end
