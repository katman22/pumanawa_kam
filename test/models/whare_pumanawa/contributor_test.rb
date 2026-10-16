require "test_helper"

class WharePumanawa::ContributorTest < ActiveSupport::TestCase
  test "creation normalizes a stable persisted slug and defaults" do
    contributor = WharePumanawa::Contributor.create!(name: "  HÉRON & Friends!  ")
    assert_equal "heron-friends", contributor.reload.slug
    assert_equal 0, contributor.position
    assert contributor.active?
    contributor.update!(name: "Renamed")
    assert_equal "heron-friends", contributor.reload.slug
    assert_raises(ActiveRecord::ReadonlyAttributeError) { contributor.slug = "new" }
  end

  test "name slug and position are validated" do
    assert_not WharePumanawa::Contributor.new(name: " ").valid?
    [ -1, nil, 1.5 ].each do |position|
      assert_not WharePumanawa::Contributor.new(name: "Artist", position: position).valid?
    end
    assert_not WharePumanawa::Contributor.new(name: "Artist", active: nil).valid?
    assert_not WharePumanawa::Contributor.new(name: "Artist", slug: "NOT Valid").valid?
  end

  test "normalized duplicate names receive distinct slugs with authoritative uniqueness" do
    first = WharePumanawa::Contributor.create!(name: "Artist_One")
    second = WharePumanawa::Contributor.create!(name: "ARTIST-ONE!")
    assert_equal "artist-one-2", second.slug
    assert_not WharePumanawa::Contributor.new(name: "Other", slug: first.slug).valid?
    assert_raises(ActiveRecord::RecordNotUnique) do
      WharePumanawa::Contributor.transaction(requires_new: true) do
        WharePumanawa::Contributor.insert_all!([ { name: "Other", slug: first.slug } ])
      end
    end
  end

  test "insert collisions retry without aborting the outer transaction" do
    first = WharePumanawa::Contributor.create!(name: "Same")
    competing = WharePumanawa::Contributor.new(name: "Same", slug: first.slug)
    competing.save!(validate: false)
    assert_match(/\Asame-[a-f0-9]{8}\z/, competing.reload.slug)
    assert WharePumanawa::Contributor.create!(name: "After retry").persisted?
  end

  test "ordering and active scope are deterministic" do
    later = WharePumanawa::Contributor.create!(name: "Later", position: 2)
    first = WharePumanawa::Contributor.create!(name: "First", position: 1)
    second = WharePumanawa::Contributor.create!(name: "Second", position: 1, active: false)
    assert_equal [ first.id, second.id, later.id ], WharePumanawa::Contributor.ordered.pluck(:id)
    assert_equal [ first.id, later.id ], WharePumanawa::Contributor.active.ordered.pluck(:id)
  end

  test "murals have a foreign keyed association and cannot be orphaned by contributor deletion" do
    contributor = WharePumanawa::Contributor.create!(name: "Artist")
    mural = contributor.murals.create!(title: "Owned mural")
    assert_equal contributor, mural.reload.contributor
    assert_equal [ mural ], contributor.murals.reload.to_a
    assert_not contributor.destroy
    assert mural.reload.persisted?
    assert_raises(ActiveRecord::InvalidForeignKey) do
      mural.class.transaction(requires_new: true) { mural.update_columns(contributor_id: -1) }
    end
    # Existing writers remain supported until the final NOT NULL rollout.
    assert WharePumanawa::Mural.create!(title: "Legacy writer").persisted?
  end

  test "database rejects null fields and negative positions" do
    %i[name slug position active].each do |field|
      attributes = { name: "Artist", slug: "db-#{field}", position: 0, active: true }.merge(field => nil)
      assert_raises(ActiveRecord::NotNullViolation) do
        WharePumanawa::Contributor.transaction(requires_new: true) { WharePumanawa::Contributor.insert_all!([ attributes ]) }
      end
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      WharePumanawa::Contributor.transaction(requires_new: true) do
        WharePumanawa::Contributor.insert_all!([ { name: "Artist", slug: "negative", position: -1 } ])
      end
    end
  end
end
