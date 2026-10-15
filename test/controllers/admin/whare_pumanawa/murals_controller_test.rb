require "test_helper"

class Admin::WharePumanawa::MuralsControllerTest < ActionDispatch::IntegrationTest
  setup do
    admin = Admin::User.create!(username: "artist", password: "a-long-test-password", role: :mural_admin)
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
    post admin_login_path, params: { username: admin.username, password: "a-long-test-password" }
  end

  test "mural admin creates edits and deletes drafts through conventional routes" do
    get new_admin_whare_pumanawa_mural_path
    assert_response :success
    assert_difference "WharePumanawa::Mural.count", 1 do
      post admin_whare_pumanawa_murals_path, params: { whare_pumanawa_mural: { title: "Blue Heron", position: 2, slug: "forged" } }
    end
    mural = ::WharePumanawa::Mural.find_by!(title: "Blue Heron")
    assert_equal "blue-heron", mural.slug
    assert_redirected_to edit_admin_whare_pumanawa_mural_path(mural, locale: :en)
    get edit_admin_whare_pumanawa_mural_path(mural)
    assert_response :success
    assert_select "input[name='whare_pumanawa_mural[slug]']", count: 0
    patch admin_whare_pumanawa_mural_path(mural), params: { whare_pumanawa_mural: { title: "Renamed", location: "Main Street", year: 2026, client: "Community", description: "Story", position: 1, slug: "forged" } }
    assert_equal "blue-heron", mural.reload.slug
    assert_equal "Main Street", mural.location
    get admin_whare_pumanawa_murals_path
    assert_response :success
    assert_includes response.body, "Renamed"
    assert_difference "WharePumanawa::Mural.count", -1 do
      delete admin_whare_pumanawa_mural_path(mural)
    end
    assert_redirected_to admin_whare_pumanawa_murals_path(locale: :en)
  end

  test "validation and incomplete publication errors are shown" do
    post admin_whare_pumanawa_murals_path, params: { whare_pumanawa_mural: { title: "" } }
    assert_response :unprocessable_entity
    assert_select "[role=alert]"
    mural = ::WharePumanawa::Mural.create!(title: "Draft")
    patch admin_whare_pumanawa_mural_path(mural), params: { whare_pumanawa_mural: { published: "1" } }
    assert_response :unprocessable_entity
    assert_not mural.reload.published?
    get whare_pumanawa_mural_path(mural.slug)
    assert_response :not_found
    photo = mural.mural_photos.build
    photo.image.attach(io: File.open(file_fixture("mural-small.jpg")), filename: "mural-small.jpg")
    photo.save!
    patch admin_whare_pumanawa_mural_path(mural), params: { whare_pumanawa_mural: { published: "1" } }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Alt text can't be blank/
    assert_not mural.reload.published?
  end

  test "valid content publishes and unpublishes without changing permalink" do
    mural = ::WharePumanawa::Mural.create!(title: "Publishable")
    photo = mural.mural_photos.build(alt_text: "Heron on a wall")
    photo.image.attach(io: File.open(file_fixture("mural-small.jpg")), filename: "mural-small.jpg")
    photo.save!
    patch admin_whare_pumanawa_mural_path(mural), params: { whare_pumanawa_mural: { published: "1" } }
    assert mural.reload.published?
    get whare_pumanawa_mural_path(mural.slug)
    assert_response :success
    patch admin_whare_pumanawa_mural_path(mural), params: { whare_pumanawa_mural: { published: "0" } }
    assert_not mural.reload.published?
    get whare_pumanawa_mural_path(mural.slug)
    assert_response :not_found
  end
end
