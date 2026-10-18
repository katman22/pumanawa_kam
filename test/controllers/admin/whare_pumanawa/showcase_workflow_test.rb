require "test_helper"
require_relative "../../../helpers/whare_pumanawa_content_helper"

class AdminShowcaseWorkflowTest < ActionDispatch::IntegrationTest
  include WharePumanawaContentHelper

  setup do
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
    @organization = WharePumanawa::Organization.create!(name: "Studio A")
    @project = @organization.projects.create!(name: "Project A")
    @foreign_organization = WharePumanawa::Organization.create!(name: "Private Studio B")
    @foreign_project = @foreign_organization.projects.create!(name: "Foreign project")
    artist = WharePumanawa::Contributor.create!(name: "Artist")
    @mural = showcase_mural(artist, title: "Mural A")
    @mural.update!(project: @project)
    @admin = Admin::User.create!(username: "org-owner", password: "a-long-test-password", role: :organization_admin)
    @organization.organization_memberships.create!(admin_user: @admin)
    post admin_login_path, params: { username: @admin.username, password: "a-long-test-password" }
  end

  test "workspace links its own active public organization showcase only" do
    get admin_root_path
    assert_response :success
    assert_select "#organization-workspace-heading + p a[href=?]", whare_pumanawa_organization_path(@organization.slug, locale: :en), text: "View showcase"
    assert_select "a[href=?]", whare_pumanawa_organization_path(@foreign_organization.slug, locale: :en), count: 0
    @organization.update!(active: false)
    get admin_root_path
    assert_select "a", text: "View showcase", count: 0
  end

  test "project creation follows collection with unchanged route and public showcase per eligible row" do
    get admin_whare_pumanawa_projects_path
    assert_response :success
    assert_select ".table-responsive + .d-flex.justify-content-end a.btn.btn-primary[href=?]", new_admin_whare_pumanawa_project_path(locale: :en), text: "New project"
    assert_select "a", text: "New project", count: 1
    assert_select "tbody tr", count: 1
    assert_select "td a[href=?]", admin_whare_pumanawa_project_path(@project, locale: :en), text: @project.name
    assert_select "td a[href=?]", whare_pumanawa_project_path(@project.slug, locale: :en), text: "View showcase"
    assert_not_includes response.body, @foreign_project.name
    @organization.update!(active: false)
    get admin_whare_pumanawa_projects_path
    assert_select "td a", text: "View showcase", count: 0
  end

  test "mural creation follows table and keeps portfolio navigation thumbnail columns and edit link" do
    get admin_whare_pumanawa_murals_path
    assert_response :success
    assert_select ".table-responsive + .d-flex.justify-content-end a.btn.btn-primary[href=?]", new_admin_whare_pumanawa_mural_path(locale: :en), text: "New mural"
    assert_select "a", text: "New mural", count: 1
    assert_equal [ "Thumbnail", "Title", "Project", "Status", "Position", "Manage" ], css_select("th").map(&:text)
    assert_select "a[href=?]", whare_pumanawa_root_path(locale: :en), text: "View portfolio"
    assert_select "a[href=?]", admin_whare_pumanawa_projects_path(locale: :en), text: "Projects"
    assert_select "a[href=?]", admin_whare_pumanawa_contributors_path(locale: :en), text: "Manage contributors"
    assert_select "td img[width='120'][height='90']"
    assert_select "td a[href=?]", edit_admin_whare_pumanawa_mural_path(@mural, locale: :en), text: "Edit Mural A"
  end

  test "public project visibility never grants admin access" do
    get whare_pumanawa_project_path(@foreign_project.slug)
    assert_response :success
    get admin_whare_pumanawa_project_path(@foreign_project)
    assert_response :forbidden
    get admin_whare_pumanawa_organization_path(@foreign_organization)
    assert_response :forbidden
  end
end
