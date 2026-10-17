require "test_helper"
require_relative "../../helpers/whare_pumanawa_content_helper"

class WharePumanawa::ProjectPublicRegressionTest < ActionDispatch::IntegrationTest
  include WharePumanawaContentHelper

  test "project grouping and inactive state do not hide published contributor or mural pages" do
    contributor = WharePumanawa::Contributor.create!(name: "Artist")
    first = showcase_mural(contributor, title: "First collaboration")
    second = showcase_mural(contributor, title: "Second collaboration")
    first.update!(project: WharePumanawa::Project.create!(name: "Active project"))
    second.update!(project: WharePumanawa::Project.create!(name: "Inactive project", active: false))
    draft = showcase_mural(contributor, title: "Hidden draft", published: false)
    draft.update!(project: first.project)
    get whare_pumanawa_contributor_path(contributor.slug)
    assert_response :success
    assert_select "figcaption", text: /First collaboration/
    assert_select "figcaption", text: /Second collaboration/
    assert_not_includes response.body, "Hidden draft"
    [ first, second ].each do |mural|
      get whare_pumanawa_mural_path(mural.slug)
      assert_response :success
      assert_select ".whare-contributor a[href=?]", whare_pumanawa_contributor_path(contributor.slug, locale: :en)
    end
    get whare_pumanawa_root_path
    assert_response :success
    assert_select ".whare-selector", count: 2
    get whare_pumanawa_mural_path(draft.slug)
    assert_response :not_found
  end
end
