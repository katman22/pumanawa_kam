require "test_helper"

class WharePumanawa::OrganizationContributorTest < ActiveSupport::TestCase
  test "explicit required foreign keys unique pairs and multiple public affiliations" do
    first = WharePumanawa::Organization.create!(name: "Studio A")
    second = WharePumanawa::Organization.create!(name: "Studio B")
    contributor = WharePumanawa::Contributor.create!(name: "Artist")
    assert_not WharePumanawa::OrganizationContributor.new.valid?
    association = first.organization_contributors.create!(contributor: contributor)
    second.organization_contributors.create!(contributor: contributor)
    assert_equal [ contributor ], first.contributors.to_a
    assert_equal [ first.id, second.id ], contributor.organizations.order(:id).pluck(:id)
    assert_not first.organization_contributors.new(contributor: contributor).valid?
    assert_raises(ActiveRecord::RecordNotUnique) do
      association.class.transaction(requires_new: true) { association.class.insert_all!([ { organization_id: first.id, contributor_id: contributor.id } ]) }
    end
    %i[organization_id contributor_id].each do |field|
      values = { organization_id: first.id, contributor_id: contributor.id }.merge(field => nil)
      assert_raises(ActiveRecord::NotNullViolation) do
        association.class.transaction(requires_new: true) { association.class.insert_all!([ values ]) }
      end
      assert_raises(ActiveRecord::InvalidForeignKey) do
        association.class.transaction(requires_new: true) { association.class.insert_all!([ values.merge(field => -1) ]) }
      end
    end
    association.destroy!
    assert contributor.reload.persisted?
    assert_equal [ second ], contributor.organizations.reload.to_a
  end
end
