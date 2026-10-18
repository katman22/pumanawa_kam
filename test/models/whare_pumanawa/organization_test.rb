require "test_helper"

class WharePumanawa::OrganizationTest < ActiveSupport::TestCase
  test "stable normalized unique slugs with defaults and authoritative database uniqueness" do
    organization = WharePumanawa::Organization.create!(name: " HÉRON_STUDIO! ")
    assert_equal "heron-studio", organization.reload.slug
    assert_equal 0, organization.position
    assert organization.active?
    organization.update!(name: "Renamed")
    assert_equal "heron-studio", organization.reload.slug
    assert_raises(ActiveRecord::ReadonlyAttributeError) { organization.slug = "other" }
    assert_equal "heron-studio-2", WharePumanawa::Organization.create!(name: "Heron Studio").slug
    assert_not WharePumanawa::Organization.new(name: "Other", slug: organization.slug).valid?
    assert_raises(ActiveRecord::RecordNotUnique) do
      organization.class.transaction(requires_new: true) { organization.class.insert_all!([ { name: "Other", slug: organization.slug } ]) }
    end
    competing = organization.class.new(name: "Same", slug: organization.slug)
    competing.save!(validate: false)
    assert_match(/\Asame-[a-f0-9]{8}\z/, competing.reload.slug)
  end

  test "required values nonnegative position ordering and active scope" do
    assert_not WharePumanawa::Organization.new(name: " ").valid?
    [ -1, nil, 1.5 ].each { |position| assert_not WharePumanawa::Organization.new(name: "Org", position: position).valid? }
    later = WharePumanawa::Organization.create!(name: "Later", position: 2)
    first = WharePumanawa::Organization.create!(name: "First", position: 1)
    second = WharePumanawa::Organization.create!(name: "Second", position: 1, active: false)
    assert_equal [ first.id, second.id, later.id ], WharePumanawa::Organization.ordered.pluck(:id)
    assert_equal [ first.id, later.id ], WharePumanawa::Organization.active.ordered.pluck(:id)
    %i[name slug position active].each do |field|
      values = { name: "DB", slug: "db-#{field}", position: 0, active: true }.merge(field => nil)
      assert_raises(ActiveRecord::NotNullViolation) do
        first.class.transaction(requires_new: true) { first.class.insert_all!([ values ]) }
      end
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      first.class.transaction(requires_new: true) { first.class.insert_all!([ { name: "Bad", slug: "negative", position: -1 } ]) }
    end
  end

  test "projects retain staged null compatibility but admin saves require a real organization" do
    organization = WharePumanawa::Organization.create!(name: "Studio")
    project = organization.projects.create!(name: "Collection")
    assert_equal organization, project.reload.organization
    assert_equal [ project ], organization.projects.to_a
    assert_not organization.destroy
    assert WharePumanawa::Project.create!(name: "Older writer").persisted?
    assert_not WharePumanawa::Project.new(name: "Admin save").valid?([ :create, :admin ])
    assert_not WharePumanawa::Project.new(name: "Forged", organization_id: -1).valid?
  end
end
