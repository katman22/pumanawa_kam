require "test_helper"

class Admin::WharePumanawa::ProjectMembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = ::WharePumanawa::Project.create!(name: "Collaboration")
    @other = ::WharePumanawa::Project.create!(name: "Other")
    @editor = Admin::User.create!(username: "artist", password: "a-long-test-password", role: :mural_admin)
    @owner = Admin::User.create!(username: "owner", password: "a-long-test-password", role: :super_admin)
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
  end

  test "super admin adds and removes eligible members and duplicates are harmless" do
    login(@owner)
    get admin_whare_pumanawa_project_path(@project)
    assert_select "select option[value='#{@editor.id}']", "artist"
    assert_select "select option[value='#{@owner.id}']", count: 0
    assert_difference "WharePumanawa::ProjectMembership.count", 1 do
      add(@editor)
    end
    assert_response :see_other
    assert @editor.can_administer_project?(@project)
    assert_no_difference "WharePumanawa::ProjectMembership.count" do
      add(@editor)
    end
    membership = @project.project_memberships.first
    delete admin_whare_pumanawa_project_project_membership_path(@other, membership)
    assert_response :not_found
    assert membership.reload.persisted?
    delete admin_whare_pumanawa_project_project_membership_path(@project, membership)
    assert_response :see_other
    assert_not @editor.can_administer_project?(@project)
  end

  test "mural admin cannot manage membership even on own project" do
    membership = @project.project_memberships.create!(admin_user: @editor)
    login(@editor)
    assert_no_difference "WharePumanawa::ProjectMembership.count" do
      add(@editor)
      assert_response :forbidden
      delete admin_whare_pumanawa_project_project_membership_path(@project, membership)
      assert_response :forbidden
    end
  end

  test "ineligible inactive canyon and super admin rows cannot be granted redundant membership" do
    login(@owner)
    canyon = Admin::User.create!(username: "canyon", password: "a-long-test-password", role: :canyon_admin)
    @editor.update!(active: false)
    [ canyon, @editor, @owner ].each do |user|
      assert_no_difference "WharePumanawa::ProjectMembership.count" do
        add(user)
      end
      assert_response :see_other
      assert flash[:alert].present?
    end
  end

  private

  def login(user)
    post admin_login_path, params: { username: user.username, password: "a-long-test-password" }
  end

  def add(user)
    post admin_whare_pumanawa_project_project_memberships_path(@project), params: { project_membership: { admin_user_id: user.id } }
  end
end
