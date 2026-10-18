require "test_helper"

class AdminOrganizationAdministrationTest < ActionDispatch::IntegrationTest
  setup do
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
    @a = WharePumanawa::Organization.create!(name: "Studio A")
    @b = WharePumanawa::Organization.create!(name: "Private Studio B")
    @project = @a.projects.create!(name: "A project")
    @other = @b.projects.create!(name: "Private project B")
    @artist = WharePumanawa::Contributor.create!(name: "Artist A")
    @foreign_artist = WharePumanawa::Contributor.create!(name: "Private Artist B")
    @association = @a.organization_contributors.create!(contributor: @artist)
    @foreign_association = @b.organization_contributors.create!(contributor: @foreign_artist)
    @mural = @project.murals.create!(title: "Mural A", contributor: @artist)
    @foreign = @other.murals.create!(title: "Private Mural B", contributor: @foreign_artist)
    @photo = @foreign.mural_photos.create!
    @admin = Admin::User.create!(username: "org-owner", password: "a-long-test-password", role: :organization_admin)
    @a.organization_memberships.create!(admin_user: @admin)
    @manager = Admin::User.create!(username: "product-owner", password: "a-long-test-password", role: :mahi_tahi_admin)
  end

  test "login lands on the single workspace and indexes reveal only assigned content" do
    login(@admin)
    assert_redirected_to admin_root_path(locale: :en)
    get admin_root_path
    assert_select "body.admin-shell--default"
    assert_select "#organization-workspace-heading", "Studio A"
    assert_select "a", text: "New project"
    assert_select "a", text: "Add contributor"
    assert_select "a", text: "Edit organization"
    assert_select "a", text: "Canyon / Resorts", count: 0
    assert_select "a", text: "Users", count: 0
    assert_select "a", text: "Mahi Tahi / Organizations", count: 0
    [ admin_whare_pumanawa_organizations_path, admin_whare_pumanawa_projects_path,
      admin_whare_pumanawa_contributors_path, admin_whare_pumanawa_murals_path ].each do |path|
      get path
      assert_response :success
      assert_not_includes response.body, "Private"
    end
    get admin_whare_pumanawa_organization_path(@a)
    assert_response :success
    assert_select "a", text: "Edit organization"
    assert_select "#organization-admins-heading", count: 0
    delete admin_logout_path
    get admin_root_path
    assert_redirected_to admin_login_path(locale: :en)
  end

  test "multiple and zero organizations produce scoped workspace choices" do
    c = WharePumanawa::Organization.create!(name: "Studio C")
    c.organization_memberships.create!(admin_user: @admin)
    login(@admin)
    get admin_root_path
    assert_select "h2", "Your organizations"
    assert_select "a[href=?]", admin_root_path(organization_id: @a.id, locale: :en), text: @a.name
    assert_select "a[href=?]", admin_root_path(organization_id: c.id, locale: :en), text: c.name
    assert_not_includes response.body, @b.name
    get admin_root_path(organization_id: c.id)
    assert_select "#organization-workspace-heading", c.name
    get admin_root_path(organization_id: @b.id)
    assert_response :forbidden
    [ admin_whare_pumanawa_projects_path(organization_id: @b.id),
      admin_whare_pumanawa_contributors_path(organization_id: @b.id),
      admin_whare_pumanawa_murals_path(organization_id: @b.id) ].each do |path|
      get path
      assert_response :forbidden
    end
    patch admin_whare_pumanawa_project_path(@project), params: { whare_pumanawa_project: { organization_id: c.id } }
    assert_response :forbidden
    assert_equal @a.id, @project.reload.organization_id
    get admin_root_path(organization_id: -1)
    assert_response :not_found
    @admin.organization_memberships.destroy_all
    get admin_root_path
    assert_response :success
    assert_select "p", text: /No organization access has been assigned/
    get admin_whare_pumanawa_organization_path(@a)
    assert_response :forbidden
  end

  test "organization admin creates and edits projects organization text contributors and real photos" do
    login(@admin)
    patch admin_whare_pumanawa_organization_path(@a), params: { whare_pumanawa_organization: { description: "Our workspace" } }
    assert_response :see_other
    post admin_whare_pumanawa_projects_path, params: { whare_pumanawa_project: { name: "New project", organization_id: @a.id } }
    assert_response :see_other
    project = @a.projects.find_by!(name: "New project")
    assert_empty project.project_memberships
    patch admin_whare_pumanawa_project_path(project), params: { whare_pumanawa_project: { description: "Our project story" } }
    assert_response :see_other
    post admin_whare_pumanawa_contributors_path, params: { organization_id: @a.id, whare_pumanawa_contributor: { name: "New artist" } }
    assert_response :see_other
    artist = @a.contributors.find_by!(name: "New artist")
    patch admin_whare_pumanawa_contributor_path(artist), params: { whare_pumanawa_contributor: { bio: "Our artist" } }
    assert_response :see_other
    post admin_whare_pumanawa_murals_path, params: { whare_pumanawa_mural: { title: "New mural", project_id: project.id, contributor_id: artist.id } }
    assert_response :see_other
    mural = project.murals.find_by!(title: "New mural")
    post admin_whare_pumanawa_mural_mural_photos_path(mural), params: { upload: { alt_text: "Painted heron", images: [ fixture_file_upload("mural.png", "image/png") ] } }
    assert_response :see_other
    photo = mural.mural_photos.first!
    assert photo.image.attached?
    assert photo.image.variant(:thumbnail).processed.download.present?
    patch admin_whare_pumanawa_mural_path(mural), params: { whare_pumanawa_mural: { published: "1", description: "Public story" } }
    assert_response :see_other
    assert mural.reload.published?
    patch admin_whare_pumanawa_mural_path(mural), params: { whare_pumanawa_mural: { published: "0" } }
    delete admin_whare_pumanawa_mural_mural_photo_path(mural, photo)
    assert_response :see_other
    assert_not ActiveStorage::Attachment.exists?(record: photo)
    delete admin_whare_pumanawa_mural_path(mural)
    assert_response :see_other
    assert_not WharePumanawa::Mural.exists?(mural.id)
  end

  test "known foreign URLs forged assignments and nested swapping are denied without mutation" do
    login(@admin)
    [ admin_whare_pumanawa_organization_path(@b), edit_admin_whare_pumanawa_organization_path(@b),
      admin_whare_pumanawa_project_path(@other), edit_admin_whare_pumanawa_mural_path(@foreign),
      edit_admin_whare_pumanawa_contributor_path(@foreign_artist) ].each do |path|
      get path
      assert_response :forbidden
    end
    get edit_admin_whare_pumanawa_mural_path(-1)
    assert_response :not_found
    assert_no_difference [ "WharePumanawa::Project.count", "WharePumanawa::Mural.count", "WharePumanawa::MuralPhoto.count", "WharePumanawa::Contributor.count", "WharePumanawa::OrganizationContributor.count" ] do
      post admin_whare_pumanawa_projects_path, params: { whare_pumanawa_project: { name: "Forged", organization_id: @b.id } }
      assert_response :forbidden
      post admin_whare_pumanawa_murals_path, params: { whare_pumanawa_mural: { title: "Forged", project_id: @other.id } }
      assert_response :forbidden
      post admin_whare_pumanawa_contributors_path, params: { organization_id: @b.id, whare_pumanawa_contributor: { name: "Forged" } }
      assert_response :forbidden
      patch admin_whare_pumanawa_project_path(@project), params: { whare_pumanawa_project: { organization_id: @b.id } }
      assert_response :forbidden
      patch admin_whare_pumanawa_mural_path(@mural), params: { whare_pumanawa_mural: { project_id: @other.id } }
      assert_response :forbidden
      patch admin_whare_pumanawa_mural_path(@mural), params: { whare_pumanawa_mural: { contributor_id: @foreign_artist.id } }
      assert_response :forbidden
      post admin_whare_pumanawa_organization_organization_contributors_path(@a), params: { organization_contributor: { contributor_id: @foreign_artist.id } }
      assert_response :forbidden
      post admin_whare_pumanawa_mural_mural_photos_path(@foreign), params: { upload: { images: [ fixture_file_upload("mural.png", "image/png") ] } }
      assert_response :forbidden
      delete admin_whare_pumanawa_mural_mural_photo_path(@foreign, @photo)
      assert_response :forbidden
      patch admin_whare_pumanawa_mural_mural_photo_path(@mural, @photo), params: { whare_pumanawa_mural_photo: { position: 9 } }
      assert_response :not_found
      delete admin_whare_pumanawa_organization_organization_contributor_path(@a, @foreign_association)
      assert_response :forbidden
    end
    assert_equal @a.id, @project.reload.organization_id
    assert_equal @project.id, @mural.reload.project_id
    assert_equal @artist.id, @mural.contributor_id
    assert_equal 0, @photo.reload.position
  end

  test "shared public contributor may be associated but shared identity and foreign affiliations stay protected" do
    @photo.update!(alt_text: "Public mural", image: fixture_file_upload("mural.png", "image/png"))
    @foreign.update!(published: true)
    login(@admin)
    post admin_whare_pumanawa_organization_organization_contributors_path(@a), params: { organization_contributor: { contributor_id: @foreign_artist.id } }
    assert_response :see_other
    association = @a.organization_contributors.find_by!(contributor: @foreign_artist)
    patch admin_whare_pumanawa_contributor_path(@foreign_artist), params: { whare_pumanawa_contributor: { name: "Changed shared name" } }
    assert_response :forbidden
    delete admin_whare_pumanawa_organization_organization_contributor_path(@a, association)
    assert_response :see_other
    assert @foreign_association.reload.persisted?
    assert @foreign_artist.reload.persisted?
  end

  test "product managers manage organization access without gaining Canyon or platform user management" do
    login(@manager)
    get admin_root_path
    assert_select "h1", "Administration"
    get admin_whare_pumanawa_organization_path(@b)
    assert_response :success
    assert_select "#organization-admins-heading", "Organization admins"
    patch admin_whare_pumanawa_organization_path(@b), params: { whare_pumanawa_organization: { description: "Product-managed identity" } }
    assert_response :see_other
    patch admin_whare_pumanawa_project_path(@project), params: { whare_pumanawa_project: { organization_id: @b.id } }
    assert_response :see_other
    assert_equal @b.id, @project.reload.organization_id
    [ admin_users_path, admin_resorts_path ].each { |path| get path; assert_response :forbidden }
    post admin_whare_pumanawa_organization_organization_memberships_path(@b), params: { organization_membership: { admin_user_id: @admin.id } }
    assert_response :see_other
    membership = @b.organization_memberships.find_by!(admin_user: @admin)
    delete admin_whare_pumanawa_organization_organization_membership_path(@a, membership)
    assert_response :not_found
    login(@admin)
    delete admin_whare_pumanawa_organization_organization_membership_path(@b, membership)
    assert_response :forbidden
    post admin_whare_pumanawa_organization_organization_memberships_path(@a), params: { organization_membership: { admin_user_id: @manager.id } }
    assert_response :forbidden
    login(@manager)
    delete admin_whare_pumanawa_organization_organization_membership_path(@b, membership)
    assert_response :see_other
    assert_not @admin.can_view_organization?(@b)
  end

  private

  def login(admin)
    post admin_login_path, params: { username: admin.username, password: "a-long-test-password" }
  end
end
