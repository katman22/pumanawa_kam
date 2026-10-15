require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = Admin::User.create!(username: "owner", password: "a-long-test-password", role: :super_admin)
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
    post admin_login_path, params: { username: @owner.username, password: "a-long-test-password" }
  end

  test "super admin lists and creates explicitly scoped administrators" do
    get admin_users_path
    assert_response :success
    get new_admin_user_path
    assert_response :success
    assert_select "option[value=mural_admin][selected]"
    assert_select "input[type=password][value]", count: 0
    assert_difference "Admin::User.count", 1 do
      post admin_users_path, params: { admin_user: { username: " Artist ", role: "mural_admin", password: "new-long-password", password_confirmation: "new-long-password" } }
    end
    assert_redirected_to admin_users_path(locale: :en)
    assert Admin::User.find_by!(username: "artist").mural_admin?
  end

  test "manual password role username and active updates work without rendering secrets" do
    user = Admin::User.create!(username: "artist", password: "old-long-password", role: :mural_admin)
    get edit_admin_user_path(user)
    assert_response :success
    assert_select "input[type=password][value]", count: 0
    patch admin_user_path(user), params: { admin_user: { username: "renamed", role: "canyon_admin", active: "0", password: "replacement-password", password_confirmation: "replacement-password" } }
    assert_redirected_to admin_users_path(locale: :en)
    assert user.reload.canyon_admin?
    assert_not user.active?
    assert_equal "renamed", user.username
    assert user.authenticate("replacement-password")
    assert_not user.authenticate("old-long-password")
    digest = user.password_digest
    patch admin_user_path(user), params: { admin_user: { active: "1", password: "", password_confirmation: "" } }
    assert user.reload.active?
    assert_equal digest, user.password_digest
    get edit_admin_user_path(user)
    assert_select "input[type=password][value]", count: 0
    assert_not_includes response.body, "replacement-password"
  end

  test "failed forms do not render submitted passwords" do
    post admin_users_path, params: { admin_user: { username: "", password: "do-not-render-this", password_confirmation: "different-password", role: "mural_admin" } }
    assert_response :unprocessable_entity
    assert_select "[role=alert]"
    assert_select "input[type=password][value]", count: 0
    assert_not_includes response.body, "do-not-render-this"
  end

  test "final active super admin protection is enforced through the controller" do
    patch admin_user_path(@owner), params: { admin_user: { active: "0" } }
    assert_response :unprocessable_entity
    assert @owner.reload.active?
    patch admin_user_path(@owner), params: { admin_user: { role: "mural_admin" } }
    assert_response :unprocessable_entity
    assert @owner.reload.super_admin?
    assert_select "[role=alert]", text: /At least one active super admin/
  end
end
