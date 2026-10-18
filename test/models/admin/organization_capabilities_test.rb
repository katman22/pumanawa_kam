require "test_helper"

class AdminOrganizationCapabilitiesTest < ActiveSupport::TestCase
  setup do
    @a = WharePumanawa::Organization.create!(name: "Studio A")
    @b = WharePumanawa::Organization.create!(name: "Studio B")
    @first = @a.projects.create!(name: "First")
    @second = @a.projects.create!(name: "Second")
    @foreign = @b.projects.create!(name: "Private")
    @mural = @first.murals.create!(title: "A mural")
  end

  test "product admins have all Mahi Tahi resources but no Canyon or platform identity authority" do
    admin = Admin::User.create!(username: "product", password: "a-long-test-password", role: :mahi_tahi_admin)
    assert admin.can_manage_mahi_tahi?
    assert_not admin.super_admin?
    assert_not admin.can_administer_canyon?
    assert_equal [ @a.id, @b.id ].sort, admin.administrable_organizations.pluck(:id).sort
    assert admin.can_administer_project?(@foreign)
    assert admin.can_administer_mural?(@mural)
    assert_empty admin.project_memberships
    assert_empty admin.organization_memberships
    admin.update!(active: false)
    assert_not admin.can_manage_mahi_tahi?
    assert_empty admin.administrable_murals
  end

  test "organization authority includes all owned projects without project memberships" do
    admin = Admin::User.create!(username: "org", password: "a-long-test-password", role: :organization_admin)
    assert_empty admin.administrable_projects
    @a.organization_memberships.create!(admin_user: admin)
    assert admin.can_administer_organization?(@a)
    assert admin.can_administer_project?(@first)
    assert admin.can_administer_project?(@second)
    assert admin.can_administer_mural?(@mural)
    assert_not admin.can_view_organization?(@b)
    assert_not admin.can_administer_project?(@foreign)
    assert_empty admin.project_memberships
    assert_equal [ @mural.id ], admin.administrable_murals.pluck(:id)
    @a.organization_memberships.destroy_all
    assert_empty admin.administrable_projects
  end

  test "narrow project members retain inferred read context without organization writes or sibling access" do
    admin = Admin::User.create!(username: "helper", password: "a-long-test-password", role: :mural_admin)
    @first.project_memberships.create!(admin_user: admin)
    assert admin.can_view_organization?(@a)
    assert_not admin.can_administer_organization?(@a)
    assert admin.can_administer_project?(@first)
    assert_not admin.can_administer_project?(@second)
    assert_not admin.can_manage_mahi_tahi?
  end
end
