require "test_helper"

class Admin::WharePumanawa::ProjectAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @project = ::WharePumanawa::Project.create!(name: "Assigned")
    @other = ::WharePumanawa::Project.create!(name: "Private project")
    @mural = @project.murals.create!(title: "Assigned mural")
    @private = @other.murals.create!(title: "Private mural")
    @editor = Admin::User.create!(username: "artist", password: "a-long-test-password", role: :mural_admin)
    @project.project_memberships.create!(admin_user: @editor)
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
    post admin_login_path, params: { username: @editor.username, password: "a-long-test-password" }
  end

  test "index and project choices are scoped while guessed mural read endpoints are forbidden" do
    get admin_whare_pumanawa_murals_path
    assert_response :success
    assert_includes response.body, "Assigned mural"
    assert_not_includes response.body, "Private mural"
    get new_admin_whare_pumanawa_mural_path
    assert_select "select[name='whare_pumanawa_mural[project_id]'] option[value='#{@project.id}']"
    assert_select "select[name='whare_pumanawa_mural[project_id]'] option[value='#{@other.id}']", count: 0
    [ admin_whare_pumanawa_mural_path(@private), edit_admin_whare_pumanawa_mural_path(@private), new_admin_whare_pumanawa_mural_path(project_id: @other.id) ].each do |path|
      get path
      assert_response :forbidden
    end
  end

  test "forged create and reassignment cannot cross project boundaries or move a stolen mural into own project" do
    assert_no_difference "WharePumanawa::Mural.count" do
      post admin_whare_pumanawa_murals_path, params: { whare_pumanawa_mural: { title: "Forged", project_id: @other.id } }
      assert_response :forbidden
    end
    patch admin_whare_pumanawa_mural_path(@mural), params: { whare_pumanawa_mural: { project_id: @other.id, title: "Forged" } }
    assert_response :forbidden
    assert_equal @project, @mural.reload.project
    assert_equal "Assigned mural", @mural.title
    patch admin_whare_pumanawa_mural_path(@private), params: { whare_pumanawa_mural: { project_id: @project.id } }
    assert_response :forbidden
    assert_equal @other, @private.reload.project
  end

  test "assigned mural edits work but clearing project is a validation error" do
    patch admin_whare_pumanawa_mural_path(@mural), params: { whare_pumanawa_mural: { title: "Edited" } }
    assert_response :see_other
    assert_equal "Edited", @mural.reload.title
    patch admin_whare_pumanawa_mural_path(@mural), params: { whare_pumanawa_mural: { project_id: "" } }
    assert_response :unprocessable_entity
    assert_equal @project, @mural.reload.project
    post admin_whare_pumanawa_murals_path, params: { whare_pumanawa_mural: { title: "No assignment" } }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Project can't be blank/
  end

  test "members can reassign only between their assigned projects and super admins may reassign across projects" do
    contributor = ::WharePumanawa::Contributor.create!(name: "Credited artist")
    @mural.update!(contributor: contributor)
    slug = @mural.slug
    @other.project_memberships.create!(admin_user: @editor)
    patch admin_whare_pumanawa_mural_path(@mural), params: { whare_pumanawa_mural: { project_id: @other.id } }
    assert_response :see_other
    assert_equal @other, @mural.reload.project
    assert_equal contributor, @mural.contributor
    assert_equal slug, @mural.slug
    owner = Admin::User.create!(username: "owner", password: "a-long-test-password", role: :super_admin)
    post admin_login_path, params: { username: owner.username, password: "a-long-test-password" }
    patch admin_whare_pumanawa_mural_path(@private), params: { whare_pumanawa_mural: { project_id: @project.id, title: "Owner edited" } }
    assert_response :see_other
    assert_equal @project, @private.reload.project
    assert_equal "Owner edited", @private.title
  end

  test "foreign photo uploads updates position changes removals publishing and mural delete are all denied" do
    photo = @private.mural_photos.create!
    assert_no_difference [ "WharePumanawa::MuralPhoto.count", "ActiveStorage::Blob.count" ] do
      post admin_whare_pumanawa_mural_mural_photos_path(@private), params: { upload: { images: [ Rack::Test::UploadedFile.new(file_fixture("mural-small.jpg"), "image/jpeg") ] } }
      assert_response :forbidden
    end
    patch admin_whare_pumanawa_mural_mural_photo_path(@private, photo), params: { whare_pumanawa_mural_photo: { position: 9, alt_text: "Tampered" } }
    assert_response :forbidden
    assert_equal 0, photo.reload.position
    delete admin_whare_pumanawa_mural_mural_photo_path(@private, photo)
    assert_response :forbidden
    assert photo.reload.persisted?
    patch admin_whare_pumanawa_mural_path(@private), params: { whare_pumanawa_mural: { published: "1" } }
    assert_response :forbidden
    assert_not @private.reload.published?
    delete admin_whare_pumanawa_mural_path(@private)
    assert_response :forbidden
    assert @private.reload.persisted?
  end

  test "revoking membership removes access without a new login and unassigned murals require super admin" do
    @project.project_memberships.destroy_all
    get edit_admin_whare_pumanawa_mural_path(@mural)
    assert_response :forbidden
    unassigned = ::WharePumanawa::Mural.create!(title: "Rollout review")
    get edit_admin_whare_pumanawa_mural_path(unassigned)
    assert_response :forbidden
    owner = Admin::User.create!(username: "owner", password: "a-long-test-password", role: :super_admin)
    post admin_login_path, params: { username: owner.username, password: "a-long-test-password" }
    get edit_admin_whare_pumanawa_mural_path(@private)
    assert_response :success
    get edit_admin_whare_pumanawa_mural_path(unassigned)
    assert_response :success
    patch admin_whare_pumanawa_mural_path(unassigned), params: { whare_pumanawa_mural: { project_id: @other.id } }
    assert_response :see_other
    assert_equal @other, unassigned.reload.project
  end
end
