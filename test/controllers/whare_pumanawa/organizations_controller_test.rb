require "test_helper"
require_relative "../../helpers/whare_pumanawa_content_helper"

class WharePumanawa::OrganizationsControllerTest < ActionDispatch::IntegrationTest
  include WharePumanawaContentHelper

  setup do
    @a = WharePumanawa::Organization.create!(name: "Studio A", description: "Stories of our community.", location: "Aotearoa", position: 1)
    @b = WharePumanawa::Organization.create!(name: "Studio B", position: 2)
    @contributor = WharePumanawa::Contributor.create!(name: "Shared artist")
    [ @a, @b ].each { |organization| organization.organization_contributors.create!(contributor: @contributor) }
    @project = @a.projects.create!(name: "Project A", active: false)
    @foreign = @b.projects.create!(name: "Project B")
    @first = showcase_mural(@contributor, title: "Mural A", photos: 2)
    @first.update!(project: @project)
    @second = showcase_mural(@contributor, title: "Mural B")
    @second.update!(project: @foreign)
  end

  test "all public pages share one bottom maker footer without a top brand lockup" do
    [
      [ whare_pumanawa_root_path, "Organizations", "Creative communities" ],
      [ whare_pumanawa_organizations_path, "Organizations", "Creative communities" ],
      [ whare_pumanawa_organization_path(@a.slug), "Studio A", "Organization showcase" ],
      [ whare_pumanawa_project_path(@project.slug), "Project A", "Project showcase" ],
      [ whare_pumanawa_contributor_path(@contributor.slug), "Shared artist", "Contributor showcase" ],
      [ whare_pumanawa_murals_path, "Murals & stories", "Selected work" ],
      [ whare_pumanawa_mural_path(@first.slug), "Murals & stories", "Selected work" ]
    ].each do |path, heading, context|
      get path
      assert_response :success
      assert_select "h1", heading
      assert_select ".whare-eyebrow", text: "Mahi Tahi · #{context}"
      assert_select ".whare-header", count: 0
      assert_select "main.whare-content + footer.whare-footer", count: 1
      assert_select ".whare-footer p", text: "Built by Whare Pūmanawa", count: 1
      assert_select ".whare-footer img.whare-maker-mark[src*='whare_pumanawa_mark_v2'][alt=''][aria-hidden='true']", count: 1
      assert_select ".showcase-signature", text: /Whare Pūmanawa/, count: 0
      assert_equal 1, response.body.scan("Whare Pūmanawa").size
    end
  end

  test "root and explicit directory list active identities without artwork collage" do
    @b.update!(active: false)
    [ whare_pumanawa_root_path, whare_pumanawa_organizations_path ].each do |path|
      get path
      assert_response :success
      assert_select "h1", "Organizations"
      assert_select "title", "Mahi Tahi"
      assert_select ".whare-header", count: 0
      assert_select ".whare-footer p", "Built by Whare Pūmanawa"
      assert_select "a[href=?]", whare_pumanawa_organization_path(@a.slug, locale: :en), text: "Studio A"
      assert_select ".organization-directory img", count: 0
      assert_select ".whare-selector, .showcase-art", count: 0
      assert_not_includes response.body, "Studio B"
      assert_not_includes response.body, "Mural A"
    end
  end

  test "organization ownership comes from project regardless of shared contributor affiliation" do
    draft = showcase_mural(@contributor, title: "Secret draft", published: false)
    draft.update!(project: @project)
    @second.update!(description: "FOREIGN PRIVATE STORY")
    inactive_contributor = WharePumanawa::Contributor.create!(name: "Inactive person", active: false)
    @a.organization_contributors.create!(contributor: inactive_contributor)
    get whare_pumanawa_organization_path(@a.slug)
    assert_response :success
    assert_select "h1", "Studio A"
    assert_select "title", "Studio A · Mahi Tahi"
    assert_select ".showcase-signature p", text: "Studio A"
    assert_select ".showcase-bio", text: /Stories of our community/
    assert_select ".showcase-art", count: 2
    assert_select ".showcase-art a[href=?]", whare_pumanawa_mural_path(@first.slug, locale: :en), count: 2
    assert_select "a[href=?]", whare_pumanawa_contributor_path(@contributor.slug, locale: :en)
    assert_select "#organization-projects + ul", text: /Project A/
    assert_not_includes response.body, "Project B"
    assert_not_includes response.body, "Mural B"
    assert_not_includes response.body, "FOREIGN PRIVATE STORY"
    assert_not_includes response.body, "Secret draft"
    assert_not_includes response.body, "Inactive person"
    assert_not_includes response.body, @second.mural_photos.first.image.blob.signed_id
  end

  test "inactive and missing organizations are 404 while existing global public URLs remain" do
    @a.update!(active: false)
    get whare_pumanawa_organization_path(@a.slug)
    assert_response :not_found
    get whare_pumanawa_organization_path("missing")
    assert_response :not_found
    get whare_pumanawa_contributor_path(@contributor.slug)
    assert_response :success
    assert_select "figcaption", text: /Mural A/
    assert_select "figcaption", text: /Mural B/
    get whare_pumanawa_mural_path(@first.slug)
    assert_response :success
    get whare_pumanawa_murals_path
    assert_response :success
    assert_select ".whare-selector", count: 2
  end

  test "organization with no published content has a useful empty state" do
    empty = WharePumanawa::Organization.create!(name: "New studio", description: "New stories")
    get whare_pumanawa_organization_path(empty.slug)
    assert_response :success
    assert_select ".whare-empty"
    assert_select ".showcase-bio", text: "New stories"
  end
end
