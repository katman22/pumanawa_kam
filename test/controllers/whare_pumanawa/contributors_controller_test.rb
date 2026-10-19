require "test_helper"
require_relative "../../helpers/whare_pumanawa_content_helper"

class WharePumanawa::ContributorsControllerTest < ActionDispatch::IntegrationTest
  include WharePumanawaContentHelper

  setup do
    @contributor = WharePumanawa::Contributor.create!(name: "Artist", bio: "Stories from our community. <script>bad()</script>", location: "Aotearoa")
  end

  test "active showcase includes only its own ordered published work and stable mural links" do
    later = showcase_mural(@contributor, title: "Later", position: 2)
    first = showcase_mural(@contributor, title: "First", position: 0, photos: 2)
    showcase_mural(@contributor, title: "Secret draft", published: false)
    other = WharePumanawa::Contributor.create!(name: "Other")
    showcase_mural(other, title: "Someone else's mural")
    get whare_pumanawa_contributor_path(@contributor.slug)
    assert_response :success
    assert_select "h1", "Artist"
    assert_select ".showcase-bio", text: /Stories from our community/
    assert_select ".showcase-bio script", count: 0
    assert_select ".showcase-intro", text: /Aotearoa/
    assert_equal [ first.title, later.title, first.title ], css_select("figcaption").map { |node| node.text.split(" · ").first }
    assert_select ".showcase-art a[href=?]", whare_pumanawa_mural_path(first.slug, locale: :en), count: 2
    assert_select ".showcase-signature", text: /Artist.*Aotearoa/m
    assert_not_includes response.body, "Secret draft"
    assert_not_includes response.body, "Someone else"
    ids = css_select(".showcase-art").map { |node| node["data-photo-id"] }
    assert_equal ids.uniq, ids
    get whare_pumanawa_mural_path(first.slug)
    assert_response :success
    assert_select ".whare-contributor a[href=?]", whare_pumanawa_contributor_path(@contributor.slug, locale: :en)
  end

  test "missing and inactive contributor are not found without hiding existing mural pages" do
    mural = showcase_mural(@contributor)
    @contributor.update!(active: false)
    get whare_pumanawa_contributor_path(@contributor.slug)
    assert_response :not_found
    get whare_pumanawa_contributor_path("missing")
    assert_response :not_found
    get whare_pumanawa_mural_path(mural.slug)
    assert_response :success
    assert_select ".whare-contributor", count: 0
  end

  test "zero published work has a friendly empty state and does not leak draft text" do
    showcase_mural(@contributor, title: "Draft only", published: false)
    get whare_pumanawa_contributor_path(@contributor.slug)
    assert_response :success
    assert_select ".whare-empty", "Published work will be shared here soon."
    assert_select ".showcase-bio"
    assert_not_includes response.body, "Draft only"
  end

  test "large showcase is bounded and metadata fallback does not trigger synchronous analysis" do
    mural = showcase_mural(@contributor, photos: 12)
    mural.mural_photos.each { |photo| photo.image.blob.update!(metadata: {}) }
    get whare_pumanawa_contributor_path(@contributor.slug)
    assert_response :success
    assert_select ".showcase-wall--full .showcase-art", count: 10
    assert_select ".showcase-art[data-orientation=neutral]", count: 10
    assert_select ".showcase-art img[alt]", count: 10
    assert_select ".showcase-text", count: 2
  end

  test "preloaded associations work under strict loading" do
    2.times { |index| showcase_mural(@contributor, title: "Preloaded #{index}", photos: 2) }
    WharePumanawa::Mural.strict_loading_by_default = true
    get whare_pumanawa_contributor_path(@contributor.slug)
    assert_response :success
    assert_select ".showcase-art", count: 4
  ensure
    WharePumanawa::Mural.strict_loading_by_default = false
  end
end
