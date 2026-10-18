require "test_helper"

class AdminShellTest < ActionDispatch::IntegrationTest
  setup do
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
    @admin = Admin::User.create!(username: "shell-owner", password: "a-long-test-password", role: :super_admin)
    @resort = Resort.create!(resort_name: "Shell test resort", slug: "shell-test", latitude: 40.6, longitude: -111.6)
    post admin_login_path, params: { username: @admin.username, password: "a-long-test-password" }
  end

  test "theme follows the current admin area rather than the account or previous page" do
    [ admin_resorts_path, new_admin_resort_path, admin_resort_cameras_path(@resort),
      new_admin_resort_resort_filter_path(@resort, kind: "alerts") ].each do |path|
      get path
      assert_response :success
      assert_select "body.admin-shell--canyon"
    end
    [ admin_root_path, admin_users_path, admin_whare_pumanawa_organizations_path,
      admin_whare_pumanawa_projects_path, admin_whare_pumanawa_contributors_path,
      admin_whare_pumanawa_murals_path ].each do |path|
      get path
      assert_response :success
      assert_select "body.admin-shell--default"
    end
  end

  test "dashboard keeps destinations and groups subordinate actions with an accessible menu" do
    get admin_root_path
    assert_response :success
    assert_select "h1", "Administration"
    assert_select "p", "Welcome, shell-owner."
    assert_select ".admin-header h4", count: 0
    assert_select ".admin-header", text: /^Admin$/, count: 0
    assert_select "button.admin-menu-toggle[aria-controls='admin-navigation'][aria-expanded='false'][hidden]"
    assert_select "nav#admin-navigation[aria-label='Administration']"
    assert_select "section[aria-labelledby='canyon-admin-heading'] a[href=?]", admin_resorts_path(locale: :en), text: "Resort Management"
    assert_select "section[aria-labelledby='users-admin-heading'] a[href=?]", admin_users_path(locale: :en), text: "Manage users"
    assert_select "section[aria-labelledby='mural-admin-heading'] .admin-dashboard-actions li", count: 5
    assert_select ".admin-footer p", "Built by Whare Pūmanawa"
    assert_select ".admin-footer img.admin-maker-mark[alt='']"
    assert_select "form[action=?][method='post'] input[name='_method'][value='delete']", admin_logout_path(locale: :en)
  end
end
