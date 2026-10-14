require "test_helper"

class AdminResourcesTest < ActionDispatch::IntegrationTest
  setup do
    @admin = Admin::User.create!(username: "editor", password: "a-long-test-password")
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
    @resort = Resort.create!(resort_name: "Admin Test Resort", slug: "admin-test", latitude: 40.6, longitude: -111.6)
    post admin_login_path, params: { username: "editor", password: "a-long-test-password" }
  end

  test "existing resort pages and update still work" do
    get admin_resorts_path
    assert_response :success
    assert_select "a[href=?]", admin_resort_path(@resort, locale: :en)
    get admin_resort_path(@resort)
    assert_response :success
    assert_select "form[action*='/parking_profiles/'][method='post']"
    get edit_admin_resort_path(@resort)
    assert_response :success
    patch admin_resort_path(@resort), params: { resort: { location: "Updated from admin" } }
    assert_redirected_to admin_resort_path(@resort, locale: :en)
    assert_equal "Updated from admin", @resort.reload.location
  end

  test "camera and filter admin remain protected and accessible" do
    get admin_resort_cameras_path(@resort)
    assert_response :success
    get new_admin_resort_resort_filter_path(@resort), params: { kind: "alerts" }
    assert_response :success
    delete admin_logout_path
    get admin_resort_cameras_path(@resort)
    assert_redirected_to admin_login_path(locale: :en)
    get new_admin_resort_resort_filter_path(@resort), params: { kind: "alerts" }
    assert_redirected_to admin_login_path(locale: :en)
  end

  test "parking creation rejects GET and POST records authenticated actor" do
    path = admin_create_parking_profile_path(resort_id: @resort.id, season: "2026-27")
    assert_no_difference "ParkingProfile.count" do
      get path
      assert_response :not_found
    end
    assert_difference "ParkingProfile.count", 1 do
      post path
    end
    profile = @resort.parking_profiles.find_by!(season: "2026-27")
    assert_redirected_to admin_edit_parking_profile_path(resort_id: @resort.id, season: "2026-27", locale: :en)
    assert_equal "admin:#{@admin.id}:editor", profile.updated_by
    patch "/admin/parking_profiles/#{@resort.id}/2026-27", params: { parking_profile: { season: "2026-27", label: "Edited profile" } }
    assert_redirected_to admin_edit_parking_profile_path(resort_id: @resort.id, season: "2026-27", locale: :en)
    assert_equal "Edited profile", profile.reload.label
    assert_equal "admin:#{@admin.id}:editor", profile.updated_by
  end

  test "long admin usernames fit the existing parking audit field" do
    @admin.update!(username: "x" * 130)
    post admin_create_parking_profile_path(resort_id: @resort.id, season: "2026-27")
    profile = @resort.parking_profiles.find_by!(season: "2026-27")
    assert_equal 120, profile.updated_by.length
    assert profile.updated_by.start_with?("admin:#{@admin.id}:")
    patch "/admin/parking_profiles/#{@resort.id}/2026-27", params: { parking_profile: { season: "2026-27", label: "Still editable" } }
    assert_redirected_to admin_edit_parking_profile_path(resort_id: @resort.id, season: "2026-27", locale: :en)
    assert_equal "Still editable", profile.reload.label
    assert_equal 120, profile.updated_by.length
  end

  test "parking mutation requires authentication and CSRF" do
    path = admin_create_parking_profile_path(resort_id: @resort.id, season: "2026-27")
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    assert_no_difference "ParkingProfile.count" do
      post path
      assert_response :unprocessable_entity
    end
    get admin_resort_path(@resort)
    token = css_select("meta[name='csrf-token']").first["content"]
    assert_difference "ParkingProfile.count", 1 do
      post path, params: { authenticity_token: token }
    end
    delete admin_logout_path, params: { authenticity_token: token }
    ActionController::Base.allow_forgery_protection = false
    assert_no_difference "ParkingProfile.count" do
      post path
      assert_redirected_to admin_login_path(locale: :en)
    end
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end
