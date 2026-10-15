require "test_helper"

class AdminRolesAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
  end

  test "roles gate direct product URLs and dashboard navigation" do
    { super_admin: [ true, true ], canyon_admin: [ true, false ], mural_admin: [ false, true ] }.each do |role, (canyon, murals)|
      admin = Admin::User.create!(username: role.to_s, password: "a-long-test-password", role: role)
      post admin_login_path, params: { username: admin.username, password: "a-long-test-password" }
      get admin_root_path
      assert_response :success
      assert_select "#canyon-admin-heading", count: canyon ? 1 : 0
      assert_select "#mural-admin-heading", count: murals ? 1 : 0
      assert_select "a[href=?]", admin_users_path(locale: :en), count: role == :super_admin ? 2 : 0
      get admin_resorts_path
      assert_response canyon ? :success : :forbidden
      get admin_whare_pumanawa_murals_path
      assert_response murals ? :success : :forbidden
      get admin_users_path
      assert_response role == :super_admin ? :success : :forbidden
      delete admin_logout_path
    end
  end

  test "mural admin cannot reach any Canyon controller or mutate resorts" do
    admin = Admin::User.create!(username: "artist", password: "a-long-test-password", role: :mural_admin)
    post admin_login_path, params: { username: admin.username, password: "a-long-test-password" }
    [ admin_resorts_path, edit_admin_resort_path(999), admin_resort_cameras_path(999), edit_admin_resort_filter_path(999),
      admin_edit_parking_profile_path(resort_id: 999, season: "2026-27") ].each do |path|
      get path
      assert_response :forbidden
    end
    assert_no_difference "Resort.count" do
      post admin_resorts_path, params: { resort: { resort_name: "Denied" } }
      assert_response :forbidden
    end
  end

  test "canyon admin cannot mutate murals photos or admin users" do
    admin = Admin::User.create!(username: "canyon", password: "a-long-test-password", role: :canyon_admin)
    post admin_login_path, params: { username: admin.username, password: "a-long-test-password" }
    assert_no_difference [ "WharePumanawa::Mural.count", "Admin::User.count" ] do
      post admin_whare_pumanawa_murals_path, params: { whare_pumanawa_mural: { title: "Denied" } }
      assert_response :forbidden
      post admin_whare_pumanawa_mural_mural_photos_path(999), params: { upload: { images: [] } }
      assert_response :forbidden
      post admin_users_path, params: { admin_user: { username: "intruder", role: "super_admin", password: "a-long-test-password" } }
      assert_response :forbidden
    end
  end

  test "role changes take effect on the next request with the same session" do
    admin = Admin::User.create!(username: "operator", password: "a-long-test-password", role: :canyon_admin)
    post admin_login_path, params: { username: admin.username, password: "a-long-test-password" }
    get admin_resorts_path
    assert_response :success
    admin.update!(role: :mural_admin)
    get admin_resorts_path
    assert_response :forbidden
    get admin_whare_pumanawa_murals_path
    assert_response :success
  end
end
