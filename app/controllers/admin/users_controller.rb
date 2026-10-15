class Admin::UsersController < Admin::BaseController
  before_action :require_super_admin!
  before_action :set_user, only: [ :edit, :update ]

  def index
    @users = Admin::User.order(:username, :id)
  end

  def new
    @user = Admin::User.new
  end

  def create
    @user = Admin::User.new(user_params)
    if @user.save
      redirect_to admin_users_path, notice: "Administrator created.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    attributes = user_params
    if attributes[:password].blank? && attributes[:password_confirmation].blank?
      attributes = attributes.except(:password, :password_confirmation)
    end
    if @user.update(attributes)
      destination = @user.id == current_admin_user.id ? admin_root_path : admin_users_path
      redirect_to destination, notice: "Administrator updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_user
    @user = Admin::User.find(params[:id])
  end

  def user_params
    params.require(:admin_user).permit(:username, :role, :active, :password, :password_confirmation)
  end
end
