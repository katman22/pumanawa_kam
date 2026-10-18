require "test_helper"

class Admin::WharePumanawa::OrganizationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @a = ::WharePumanawa::Organization.create!(name: "Studio A", description: "Shared creative place", location: "Aotearoa")
    @b = ::WharePumanawa::Organization.create!(name: "Studio B")
    @project = @a.projects.create!(name: "Assigned project")
    @hidden = @a.projects.create!(name: "Unassigned project")
    @foreign = @b.projects.create!(name: "Foreign project")
    @owner = Admin::User.create!(username: "owner", password: "a-long-test-password", role: :super_admin)
    @editor = Admin::User.create!(username: "artist", password: "a-long-test-password", role: :mural_admin)
    @project.project_memberships.create!(admin_user: @editor)
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
  end

  test "creation action follows the organization list and is right aligned" do
    @b.update!(active: false)
    login(@owner)
    get admin_whare_pumanawa_organizations_path
    assert_response :success
    assert_select "h1", "Mahi Tahi organizations"
    assert_select "h1 + ul" do
      assert_select "li", text: "Studio A · Active"
      assert_select "li", text: "Studio B · Inactive"
      assert_select "a[href=?]", admin_whare_pumanawa_organization_path(@a, locale: :en), text: @a.name
      assert_select "a[href=?]", admin_whare_pumanawa_organization_path(@b, locale: :en), text: @b.name
    end
    assert_select "ul + .d-flex.justify-content-end a.btn.btn-primary[href=?]",
      new_admin_whare_pumanawa_organization_path(locale: :en), text: "New organization", count: 1
    assert_select "a", text: "New organization", count: 1
    assert_select "nav a[href=?]", admin_whare_pumanawa_organizations_path(locale: :en), text: "Mahi Tahi / Organizations"
  end

  test "super admin CRUD has stable slugs validation and no delete route" do
    login(@owner)
    get admin_whare_pumanawa_organizations_path
    assert_response :success
    assert_link_texts [ @a.name, @b.name ]
    get new_admin_whare_pumanawa_organization_path
    assert_response :success
    post admin_whare_pumanawa_organizations_path, params: { whare_pumanawa_organization: { name: "New studio", slug: "forged" } }
    assert_response :see_other
    studio = ::WharePumanawa::Organization.find_by!(name: "New studio")
    assert_equal "new-studio", studio.slug
    get edit_admin_whare_pumanawa_organization_path(studio)
    assert_response :success
    assert_select "input[name='whare_pumanawa_organization[slug]']", count: 0
    patch admin_whare_pumanawa_organization_path(studio), params: { whare_pumanawa_organization: { name: "Renamed", active: "0", position: 2 } }
    assert_response :see_other
    assert_not studio.reload.active?
    assert_equal "new-studio", studio.slug
    post admin_whare_pumanawa_organizations_path, params: { whare_pumanawa_organization: { name: "" } }
    assert_response :unprocessable_entity
    assert_select "[role=alert]"
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/admin/whare_pumanawa/organizations/#{@a.id}", method: :delete) }
  end

  test "member sees inferred organizations and only their projects without organization write access" do
    login(@editor)
    get admin_whare_pumanawa_organizations_path
    assert_link_texts [ @a.name ]
    assert_select "a", text: "New organization", count: 0
    assert_select "a", text: @b.name, count: 0
    get admin_whare_pumanawa_organization_path(@a)
    assert_response :success
    assert_link_texts [ @project.name ]
    assert_not_includes response.body, @hidden.name
    assert_select "a", text: "Edit organization", count: 0
    get admin_whare_pumanawa_organization_path(@b)
    assert_response :forbidden
    get edit_admin_whare_pumanawa_organization_path(@a)
    assert_response :forbidden
    post admin_whare_pumanawa_organizations_path, params: { whare_pumanawa_organization: { name: "Denied" } }
    assert_response :forbidden
    patch admin_whare_pumanawa_organization_path(@a), params: { whare_pumanawa_organization: { name: "Denied" } }
    assert_response :forbidden
    assert_equal "Studio A", @a.reload.name
    get admin_whare_pumanawa_project_path(@hidden)
    assert_response :forbidden
  end

  test "project creation options are inferred and members cannot move projects even between visible organizations" do
    login(@editor)
    get new_admin_whare_pumanawa_project_path
    assert_select "select[name='whare_pumanawa_project[organization_id]'] option[value='#{@a.id}']"
    assert_select "option[value='#{@b.id}']", count: 0
    post admin_whare_pumanawa_projects_path, params: { whare_pumanawa_project: { name: "Forged", organization_id: @b.id } }
    assert_response :forbidden
    @foreign.project_memberships.create!(admin_user: @editor)
    patch admin_whare_pumanawa_project_path(@project), params: { whare_pumanawa_project: { organization_id: @b.id } }
    assert_response :forbidden
    assert_equal @a, @project.reload.organization
    post admin_whare_pumanawa_projects_path, params: { whare_pumanawa_project: { name: "Allowed", organization_id: @a.id } }
    assert_response :see_other
    created = ::WharePumanawa::Project.find_by!(name: "Allowed")
    assert @editor.can_administer_project?(created)
    login(@owner)
    patch admin_whare_pumanawa_project_path(@project), params: { whare_pumanawa_project: { organization_id: @b.id } }
    assert_response :see_other
    assert_equal @b, @project.reload.organization
    assert @editor.can_administer_project?(@project)
  end

  test "new mural admins need bootstrap and stale roles or inactive users get no context" do
    newcomer = Admin::User.create!(username: "newcomer", password: "a-long-test-password", role: :mural_admin)
    login(newcomer)
    assert_empty newcomer.administrable_organizations
    post admin_whare_pumanawa_projects_path, params: { whare_pumanawa_project: { name: "No context", organization_id: @a.id } }
    assert_response :forbidden
    post admin_whare_pumanawa_projects_path, params: { whare_pumanawa_project: { name: "No organization" } }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Organization can't be blank/
    @editor.update!(role: :canyon_admin)
    login(@editor)
    get admin_whare_pumanawa_organizations_path
    assert_response :forbidden
    assert_empty @editor.administrable_organizations
    @editor.update!(role: :mural_admin, active: false)
    assert_not @editor.can_view_organization?(@a)
    assert_empty @editor.administrable_organizations
    get admin_whare_pumanawa_organization_path(@a)
    assert_redirected_to admin_login_path(locale: :en)
  end

  private

  def login(user)
    post admin_login_path, params: { username: user.username, password: "a-long-test-password" }
  end

  def assert_link_texts(texts)
    texts.each { |text| assert_select "a", text: text }
  end
end
