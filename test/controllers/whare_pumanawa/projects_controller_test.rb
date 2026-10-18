require "test_helper"
require_relative "../../helpers/whare_pumanawa_content_helper"

class WharePumanawa::ProjectsControllerTest < ActionDispatch::IntegrationTest
  include WharePumanawaContentHelper

  setup do
    @organization = WharePumanawa::Organization.create!(name: "Studio A")
    @project = @organization.projects.create!(name: "Project A", description: "Our shared project story.", location: "Aotearoa")
    @sibling = @organization.projects.create!(name: "Sibling project")
    artist = WharePumanawa::Contributor.create!(name: "Shared artist")
    @mural = showcase_mural(artist, title: "Project mural", photos: 2)
    @mural.update!(project: @project)
    @other = showcase_mural(artist, title: "Sibling mural")
    @other.update!(project: @sibling, description: "SIBLING STORY")
    draft = showcase_mural(artist, title: "Draft mural", published: false)
    draft.update!(project: @project)
  end

  test "project showcase reuses the public wall and includes only its published murals" do
    get whare_pumanawa_project_path(@project.slug)
    assert_response :success
    assert_select "title", "Project A · Mahi Tahi"
    assert_select "h1", "Project A"
    assert_select ".showcase-intro", text: /Aotearoa/
    assert_select ".showcase-bio", text: /Our shared project story/
    assert_select ".showcase-intro a[href=?]", whare_pumanawa_organization_path(@organization.slug, locale: :en), text: "Studio A"
    assert_select ".showcase-wall", count: 1
    assert_select ".showcase-art", count: 2
    assert_select ".showcase-art a[href=?]", whare_pumanawa_mural_path(@mural.slug, locale: :en), count: 2
    assert_equal 2, css_select(".showcase-art").map { |node| node["data-photo-id"] }.uniq.length
    assert_not_includes response.body, "Sibling mural"
    assert_not_includes response.body, "SIBLING STORY"
    assert_not_includes response.body, "Draft mural"
    assert_not_includes response.body, @other.mural_photos.first.image.blob.signed_id
  end

  test "inactive project remains public but inactive organization and missing project do not resolve" do
    @project.update!(active: false)
    get whare_pumanawa_project_path(@project.slug)
    assert_response :success
    @organization.update!(active: false)
    get whare_pumanawa_project_path(@project.slug)
    assert_response :not_found
    get whare_pumanawa_project_path("missing")
    assert_response :not_found
    legacy = WharePumanawa::Project.create!(name: "Unassigned legacy project")
    get whare_pumanawa_project_path(legacy.slug)
    assert_response :not_found
  end

  test "zero published murals uses the existing graceful empty state" do
    empty = @organization.projects.create!(name: "New project", description: "A story to come")
    get whare_pumanawa_project_path(empty.slug)
    assert_response :success
    assert_select "h1", "New project"
    assert_select ".showcase-bio", "A story to come"
    assert_select ".whare-empty", "Published work will be shared here soon."
    assert_select ".showcase-art", count: 0
  end
end
