require "test_helper"

class WharePumanawa::MuralsControllerTest < ActionDispatch::IntegrationTest
  test "index handles zero published murals and ignores drafts" do
    WharePumanawa::Mural.create!(title: "Secret draft")
    get whare_pumanawa_root_path
    assert_response :success
    assert_select "h1", "Murals & stories"
    assert_select ".whare-empty", "New work will be shared here soon."
    assert_not_includes response.body, "Secret draft"
    assert_not_includes response.body, "Aura Weather"
    assert_select ".whare-hero", count: 0
  end

  test "index selects first published mural by position then id and renders content" do
    later = published_mural("Later", position: 3)
    first = published_mural("Blue Heron", position: 1)
    second = published_mural("Second", position: 1)
    first.update!(location: "Main Street", year: 2026, client: "Community", description: "A plain-text story.\n\n<script>alert('no')</script>")
    photo = first.mural_photos.build(alt_text: "Supporting detail", position: 1)
    photo.image.attach(io: File.open(file_fixture("mural.png")), filename: "mural.png")
    photo.save!
    WharePumanawa::Mural.create!(title: "Private draft")
    get whare_pumanawa_root_path
    assert_response :success
    assert_select "#mural-title", "Blue Heron"
    assert_equal [ first.title, second.title, later.title ], css_select(".whare-mural-links a").map(&:text)
    assert_select ".whare-hero[alt='Blue Heron painted on a wall']", count: 1
    assert_select ".whare-supporting img[alt='Supporting detail']", count: 1
    assert_select ".whare-metadata", text: /Main Street.*2026.*Community/m
    assert_select ".whare-story", text: /plain-text story/
    assert_select ".whare-story script", count: 0
    assert_not_includes response.body, "Private draft"
  end

  test "show uses stable slug selects requested mural and excludes drafts" do
    first = published_mural("First")
    requested = published_mural("Second")
    requested.update!(title: "Renamed Work")
    draft = WharePumanawa::Mural.create!(title: "Hidden")
    get whare_pumanawa_mural_path(requested.slug)
    assert_response :success
    assert_select "#mural-title", "Renamed Work"
    assert_select "a[rel='bookmark'][href=?]", whare_pumanawa_mural_path("second", locale: :en)
    assert_select ".whare-mural-links a", count: 2
    assert_not_includes response.body, draft.title
    get whare_pumanawa_mural_path(draft.slug)
    assert_response :not_found
    get whare_pumanawa_mural_path("missing")
    assert_response :not_found
    assert WharePumanawa::Mural.published.exists?(first.id)
  end

  test "invalid photo content cannot be exposed by public rendering" do
    mural = published_mural("Safe rendering")
    mural.mural_photos.first.update_columns(alt_text: " ")
    get whare_pumanawa_mural_path(mural.slug)
    assert_response :success
    assert_select "#mural-title", mural.title
    assert_select ".whare-hero", count: 0
  end

  test "public views use preloaded photos and attachments for multiple murals" do
    3.times { |i| published_mural("Preloaded #{i}") }
    WharePumanawa::Mural.strict_loading_by_default = true
    get whare_pumanawa_root_path
    assert_response :success
    assert_select ".whare-hero", count: 1
  ensure
    WharePumanawa::Mural.strict_loading_by_default = false
  end

  private

  def published_mural(title, position: 0)
    mural = WharePumanawa::Mural.create!(title: title, position: position)
    photo = mural.mural_photos.build(alt_text: "#{title} painted on a wall")
    photo.image.attach(io: File.open(file_fixture("mural.png")), filename: "mural.png")
    photo.save!
    mural.update!(published: true)
    mural
  end
end
