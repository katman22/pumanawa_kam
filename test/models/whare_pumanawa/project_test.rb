require "test_helper"

class WharePumanawa::ProjectTest < ActiveSupport::TestCase
  test "stable unique normalized slugs and defaults" do
    project = WharePumanawa::Project.create!(name: "  Our_SHARED HÉRON!  ")
    assert_equal "our-shared-heron", project.reload.slug
    assert project.active?
    assert_equal 0, project.position
    project.update!(name: "Renamed")
    assert_equal "our-shared-heron", project.reload.slug
    assert_raises(ActiveRecord::ReadonlyAttributeError) { project.slug = "changed" }
    duplicate = WharePumanawa::Project.create!(name: "Our shared heron")
    assert_equal "our-shared-heron-2", duplicate.slug
    assert_not WharePumanawa::Project.new(name: "Other", slug: project.slug).valid?
    assert_raises(ActiveRecord::RecordNotUnique) do
      WharePumanawa::Project.transaction(requires_new: true) { WharePumanawa::Project.insert_all!([ { name: "Other", slug: project.slug } ]) }
    end
  end

  test "slug creation collisions retry inside a savepoint" do
    existing = WharePumanawa::Project.create!(name: "Same")
    collision = WharePumanawa::Project.new(name: "Same", slug: existing.slug)
    collision.save!(validate: false)
    assert_match(/\Asame-[a-f0-9]{8}\z/, collision.reload.slug)
    assert WharePumanawa::Project.create!(name: "After collision").persisted?
  end

  test "validation ordering active scope and database constraints" do
    assert_not WharePumanawa::Project.new(name: " ").valid?
    [ -1, nil, 1.5 ].each { |position| assert_not WharePumanawa::Project.new(name: "Position", position: position).valid? }
    assert_not WharePumanawa::Project.new(name: "Active", active: nil).valid?
    later = WharePumanawa::Project.create!(name: "Later", position: 3)
    first = WharePumanawa::Project.create!(name: "First", position: 1)
    second = WharePumanawa::Project.create!(name: "Second", position: 1, active: false)
    assert_equal [ first.id, second.id, later.id ], WharePumanawa::Project.ordered.pluck(:id)
    assert_equal [ first.id, later.id ], WharePumanawa::Project.active.ordered.pluck(:id)
    %i[name slug position active].each do |field|
      attributes = { name: "Constraint", slug: "constraint-#{field}", position: 0, active: true }.merge(field => nil)
      assert_raises(ActiveRecord::NotNullViolation) do
        WharePumanawa::Project.transaction(requires_new: true) { WharePumanawa::Project.insert_all!([ attributes ]) }
      end
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      WharePumanawa::Project.transaction(requires_new: true) { WharePumanawa::Project.insert_all!([ { name: "Negative", slug: "negative", position: -1 } ]) }
    end
  end

  test "project and contributor stay separate and project cannot orphan murals" do
    project = WharePumanawa::Project.create!(name: "Collection")
    contributor = WharePumanawa::Contributor.create!(name: "Artist")
    mural = project.murals.create!(title: "Our mural", contributor: contributor)
    assert_equal project, mural.reload.project
    assert_equal contributor, mural.contributor
    assert_equal [ mural ], project.murals.to_a
    assert_not project.destroy
    assert mural.reload.persisted?
    assert WharePumanawa::Mural.create!(title: "Legacy writer").persisted?
    assert_not WharePumanawa::Mural.new(title: "Admin writer").valid?([ :create, :admin ])
  end
end
