require "test_helper"

class Admin::WharePumanawa::OrganizationContributorsControllerTest < ActionDispatch::IntegrationTest
  test "super admin associates removes and cannot delete a wrong-parent affiliation" do
    organization = ::WharePumanawa::Organization.create!(name: "Studio")
    other = ::WharePumanawa::Organization.create!(name: "Other")
    contributor = ::WharePumanawa::Contributor.create!(name: "Artist")
    owner = Admin::User.create!(username: "owner", password: "a-long-test-password", role: :super_admin)
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
    post admin_login_path, params: { username: owner.username, password: "a-long-test-password" }
    assert_difference "WharePumanawa::OrganizationContributor.count", 1 do
      post admin_whare_pumanawa_organization_organization_contributors_path(organization), params: { organization_contributor: { contributor_id: contributor.id } }
    end
    assert_response :see_other
    association = organization.organization_contributors.first
    assert_no_difference "WharePumanawa::OrganizationContributor.count" do
      post admin_whare_pumanawa_organization_organization_contributors_path(organization), params: { organization_contributor: { contributor_id: contributor.id } }
    end
    delete admin_whare_pumanawa_organization_organization_contributor_path(other, association)
    assert_response :not_found
    delete admin_whare_pumanawa_organization_organization_contributor_path(organization, association)
    assert_response :see_other
    assert contributor.reload.persisted?
  end

  test "association confers no authentication scope and project members cannot manage it" do
    organization = ::WharePumanawa::Organization.create!(name: "Studio")
    contributor = ::WharePumanawa::Contributor.create!(name: "Artist")
    association = organization.organization_contributors.create!(contributor: contributor)
    editor = Admin::User.create!(username: "artist", password: "a-long-test-password", role: :mural_admin)
    project = organization.projects.create!(name: "Project")
    assert_not editor.can_view_organization?(organization)
    project.project_memberships.create!(admin_user: editor)
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
    post admin_login_path, params: { username: editor.username, password: "a-long-test-password" }
    assert_no_difference "WharePumanawa::OrganizationContributor.count" do
      post admin_whare_pumanawa_organization_organization_contributors_path(organization), params: { organization_contributor: { contributor_id: contributor.id } }
      assert_response :forbidden
      delete admin_whare_pumanawa_organization_organization_contributor_path(organization, association)
      assert_response :forbidden
    end
  end
end
