class Admin::SessionsController < ApplicationController
  layout "admin_login"

  ARTWORK = %w[
    IMG_6245-Edit.jpg IMG_6377.JPG IMG_6390.JPG IMG_6395.JPG
    IMG_6417.JPG IMG_6429.JPG IMG_6435.JPG
  ].freeze
  LOGIN_ATTEMPTS = ActiveSupport::Cache::MemoryStore.new(size: 1.megabyte)

  before_action :prevent_caching
  rate_limit to: 10, within: 3.minutes, store: LOGIN_ATTEMPTS, only: :create,
    with: -> { show_error("Too many attempts. Please try again shortly.", :too_many_requests) }

  def new
    @artwork = ARTWORK.sample
  end

  def create
    user = Admin::User.authenticate_by(username: params[:username].to_s.strip.downcase, password: params[:password].to_s)
    if user&.active?
      reset_session
      session[:admin_user_id] = user.id
      redirect_to admin_root_path, status: :see_other
    else
      show_error("Unable to sign in. Check your credentials and try again.", :unprocessable_entity)
    end
  end

  def destroy
    reset_session
    redirect_to admin_login_path, status: :see_other
  end

  private

  def prevent_caching
    response.headers["Cache-Control"] = "no-store"
  end

  def show_error(message, status)
    @error = message
    @artwork = ARTWORK.sample
    render :new, status: status
  end
end
