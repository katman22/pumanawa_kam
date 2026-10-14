require "test_helper"

class WharePumanawa::MuralTest < ActiveSupport::TestCase
  test "valid creation generates a normalized persisted slug and draft defaults" do
    mural = WharePumanawa::Mural.create!(title: "  Blue HÉRON on Main Street!  ")
    assert_equal "blue-heron-on-main-street", mural.reload.slug
    assert_equal 0, mural.position
    assert_equal false, mural.published
  end

  test "title is required" do
    mural = WharePumanawa::Mural.new(title: " ")
    assert_not mural.valid?
    assert mural.errors[:title].present?
  end

  test "slug remains unchanged when title changes and is read only" do
    mural = WharePumanawa::Mural.create!(title: "Blue Heron")
    mural.update!(title: "Another Title")
    assert_equal "blue-heron", mural.reload.slug
    assert_raises(ActiveRecord::ReadonlyAttributeError) { mural.slug = "changed" }
  end

  test "duplicate and normalized duplicate titles have distinct slugs" do
    first = WharePumanawa::Mural.create!(title: "Blue Heron")
    second = WharePumanawa::Mural.create!(title: "Blue Heron")
    third = WharePumanawa::Mural.create!(title: "BLUE-HERON!")
    assert_equal "blue-heron", first.slug
    assert_equal "blue-heron-2", second.slug
    assert_equal "blue-heron-3", third.slug
  end

  test "a title with no slug characters has a safe fallback" do
    mural = WharePumanawa::Mural.create!(title: "🎨")
    assert_equal "mural", mural.slug
  end

  test "model validates slug uniqueness and format" do
    existing = WharePumanawa::Mural.create!(title: "Existing")
    duplicate = WharePumanawa::Mural.new(title: "Other", slug: existing.slug)
    assert_not duplicate.valid?
    assert duplicate.errors[:slug].present?
    assert_not WharePumanawa::Mural.new(title: "Bad", slug: "UPPER CASE").valid?
  end

  test "database enforces slug uniqueness without model validation" do
    existing = WharePumanawa::Mural.create!(title: "Database Constraint")
    assert_raises(ActiveRecord::RecordNotUnique) do
      WharePumanawa::Mural.transaction(requires_new: true) do
        WharePumanawa::Mural.insert_all!([ { title: "Other", slug: existing.slug } ])
      end
    end
    assert_equal 1, WharePumanawa::Mural.where(slug: existing.slug).count
  end

  test "a creation uniqueness race is retried inside a savepoint" do
    existing = WharePumanawa::Mural.create!(title: "Same Title")
    # Skip the pre-insert uniqueness check to exercise the real DB conflict path.
    competing = WharePumanawa::Mural.new(title: "Same Title", slug: existing.slug)
    assert competing.save!(validate: false)
    assert_match(/\Asame-title-[a-f0-9]{8}\z/, competing.reload.slug)
    assert_not_equal existing.slug, competing.slug
    # The outer transaction must remain usable after the failed insert.
    assert WharePumanawa::Mural.create!(title: "After Retry").persisted?
  end

  test "positions are nonnegative integers" do
    [ -1, nil, 1.5 ].each { |position| assert_not WharePumanawa::Mural.new(title: "Position", position: position).valid? }
    assert WharePumanawa::Mural.new(title: "Position", position: 0).valid?
  end

  test "ordering is deterministic by position then id" do
    later = WharePumanawa::Mural.create!(title: "Later", position: 3)
    first = WharePumanawa::Mural.create!(title: "First", position: 1)
    second = WharePumanawa::Mural.create!(title: "Second", position: 1)
    assert_equal [ first.id, second.id, later.id ], WharePumanawa::Mural.ordered.pluck(:id)
  end

  test "database rejects missing title slug position and publication values" do
    %i[title slug position published].each do |field|
      values = { title: "Constraint", slug: "constraint-#{field}", position: 0, published: false }.merge(field => nil)
      assert_raises(ActiveRecord::NotNullViolation) do
        WharePumanawa::Mural.transaction(requires_new: true) { WharePumanawa::Mural.insert_all!([ values ]) }
      end
    end
  end

  test "database enforces nonnegative position" do
    assert_raises(ActiveRecord::StatementInvalid) do
      WharePumanawa::Mural.transaction(requires_new: true) do
        WharePumanawa::Mural.insert_all!([ { title: "Negative", slug: "negative", position: -1 } ])
      end
    end
  end

  test "publication requires a photo and public alt text" do
    mural = WharePumanawa::Mural.create!(title: "Publication")
    assert_not mural.update(published: true)
    mural.published = false
    photo = mural.mural_photos.create!
    photo.image.attach(io: File.open(file_fixture("mural.png")), filename: "mural.png", content_type: "image/png")
    assert_not mural.update(published: true)
    mural.published = false
    photo.update!(alt_text: "A blue heron painted on a wall")
    mural.reload
    assert mural.update(published: true)
    assert_includes WharePumanawa::Mural.published, mural
  end
end
