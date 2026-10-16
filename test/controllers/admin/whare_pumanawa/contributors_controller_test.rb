require "test_helper"

class Admin::WharePumanawa::ContributorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
  end

  test "mural and super admins manage contributors with stable slugs and no deletion route" do
    %i[mural_admin super_admin].each do |role|
      login(role)
      get admin_whare_pumanawa_contributors_path
      assert_response :success
      get new_admin_whare_pumanawa_contributor_path
      assert_response :success
      post admin_whare_pumanawa_contributors_path, params: { whare_pumanawa_contributor: { name: role.to_s, slug: "forged", bio: "An artist", location: "Aotearoa", position: 2 } }
      assert_response :see_other
      contributor = ::WharePumanawa::Contributor.find_by!(name: role.to_s)
      slug = contributor.slug
      assert_not_equal "forged", slug
      get edit_admin_whare_pumanawa_contributor_path(contributor)
      assert_response :success
      assert_select "input[name='whare_pumanawa_contributor[slug]']", count: 0
      patch admin_whare_pumanawa_contributor_path(contributor), params: { whare_pumanawa_contributor: { name: "Renamed #{role}", active: "0", slug: "changed" } }
      assert_response :see_other
      assert_not contributor.reload.active?
      assert_equal slug, contributor.slug
      patch admin_whare_pumanawa_contributor_path(contributor), params: { whare_pumanawa_contributor: { active: "1" } }
      assert contributor.reload.active?
      assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/admin/whare_pumanawa/contributors/#{contributor.id}", method: :delete) }
      delete admin_logout_path
    end
  end

  test "canyon admin cannot read or mutate contributors through direct URLs" do
    login(:canyon_admin)
    get admin_whare_pumanawa_contributors_path
    assert_response :forbidden
    get edit_admin_whare_pumanawa_contributor_path(999)
    assert_response :forbidden
    assert_no_difference "WharePumanawa::Contributor.count" do
      post admin_whare_pumanawa_contributors_path, params: { whare_pumanawa_contributor: { name: "Denied" } }
      assert_response :forbidden
    end
  end

  test "validation errors render and mural forms assign contributors" do
    login(:mural_admin)
    post admin_whare_pumanawa_contributors_path, params: { whare_pumanawa_contributor: { name: "" } }
    assert_response :unprocessable_entity
    assert_select "[role=alert]"
    contributor = ::WharePumanawa::Contributor.create!(name: "Artist")
    get new_admin_whare_pumanawa_mural_path
    assert_select "select[name='whare_pumanawa_mural[contributor_id]'] option[value='#{contributor.id}']", "Artist"
    post admin_whare_pumanawa_murals_path, params: { whare_pumanawa_mural: { title: "Assigned", contributor_id: contributor.id } }
    assert_response :see_other
    mural = ::WharePumanawa::Mural.find_by!(title: "Assigned")
    assert_equal contributor, mural.contributor
    other = ::WharePumanawa::Contributor.create!(name: "Other")
    patch admin_whare_pumanawa_mural_path(mural), params: { whare_pumanawa_mural: { contributor_id: other.id } }
    assert_equal other, mural.reload.contributor
  end

  private

  def login(role)
    admin = Admin::User.create!(username: role.to_s, password: "a-long-test-password", role: role)
    post admin_login_path, params: { username: admin.username, password: "a-long-test-password" }
  end
end
