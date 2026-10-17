require "test_helper"

class Admin::WharePumanawa::ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = ::WharePumanawa::Project.create!(name: "Assigned project", description: "Shared work", location: "Aotearoa")
    @other = ::WharePumanawa::Project.create!(name: "Other project")
    @editor = Admin::User.create!(username: "artist", password: "a-long-test-password", role: :mural_admin)
    @owner = Admin::User.create!(username: "owner", password: "a-long-test-password", role: :super_admin)
    @project.project_memberships.create!(admin_user: @editor)
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
  end

  test "super admin sees edits and creates every project without membership" do
    login(@owner)
    get admin_whare_pumanawa_projects_path
    assert_response :success
    assert_select "td a", text: @project.name
    assert_select "td a", text: @other.name
    get edit_admin_whare_pumanawa_project_path(@other)
    assert_response :success
    patch admin_whare_pumanawa_project_path(@other), params: { whare_pumanawa_project: { name: "Renamed", active: "0", slug: "forged" } }
    assert_response :see_other
    assert_equal "other-project", @other.reload.slug
    assert_not @other.active?
    assert_no_difference "WharePumanawa::ProjectMembership.count" do
      post admin_whare_pumanawa_projects_path, params: { whare_pumanawa_project: { name: "Owner project" } }
    end
    assert_response :see_other
  end

  test "mural admin sees only assigned projects and cannot guess show edit update URLs" do
    login(@editor)
    get admin_whare_pumanawa_projects_path
    assert_response :success
    assert_select "td a", text: @project.name
    assert_select "td a", text: @other.name, count: 0
    get admin_whare_pumanawa_project_path(@project)
    assert_response :success
    assert_includes response.body, "Shared work"
    assert_includes response.body, @editor.username
    assert_select "input[type=submit][value='Add member']", count: 0
    [ admin_whare_pumanawa_project_path(@other), edit_admin_whare_pumanawa_project_path(@other) ].each do |path|
      get path
      assert_response :forbidden
    end
    patch admin_whare_pumanawa_project_path(@other), params: { whare_pumanawa_project: { name: "Denied" } }
    assert_response :forbidden
    assert_equal "Other project", @other.reload.name
    patch admin_whare_pumanawa_project_path(@project), params: { whare_pumanawa_project: { description: "Edited together" } }
    assert_response :see_other
    assert_equal "Edited together", @project.reload.description
  end

  test "mural admin creates a project with atomic initial self membership and handles errors" do
    login(@editor)
    post admin_whare_pumanawa_projects_path, params: { whare_pumanawa_project: { name: "" } }
    assert_response :unprocessable_entity
    assert_select "[role=alert]"
    assert_difference [ "WharePumanawa::Project.count", "WharePumanawa::ProjectMembership.count" ], 1 do
      post admin_whare_pumanawa_projects_path, params: { whare_pumanawa_project: { name: "New collaboration" } }
    end
    assert_response :see_other
    project = ::WharePumanawa::Project.find_by!(name: "New collaboration")
    assert @editor.can_administer_project?(project)
  end

  test "canyon role is denied even with a stale membership and project delete is unavailable" do
    @editor.update!(role: :canyon_admin)
    login(@editor)
    get admin_whare_pumanawa_projects_path
    assert_response :forbidden
    get admin_whare_pumanawa_project_path(@project)
    assert_response :forbidden
    post admin_whare_pumanawa_projects_path, params: { whare_pumanawa_project: { name: "Denied" } }
    assert_response :forbidden
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/admin/whare_pumanawa/projects/#{@project.id}", method: :delete) }
  end

  private

  def login(user)
    post admin_login_path, params: { username: user.username, password: "a-long-test-password" }
  end
end
