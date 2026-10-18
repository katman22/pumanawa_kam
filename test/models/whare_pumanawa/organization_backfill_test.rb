require "test_helper"
require Rails.root.join("db/migrate/20261017000001_add_whare_pumanawa_organizations")
require_relative "../../helpers/whare_pumanawa_content_helper"

class WharePumanawa::OrganizationBackfillTest < ActiveSupport::TestCase
  include WharePumanawaContentHelper

  test "backfill preserves project membership artwork attribution attachments timestamps and unrelated rows" do
    contributor = WharePumanawa::Contributor.create!(name: "Artist")
    mural = showcase_mural(contributor)
    project = WharePumanawa::Project.create!(name: "Legacy collection")
    mural.update!(project: project)
    editor = Admin::User.create!(username: "artist", password: "a-long-test-password", role: :mural_admin)
    membership = project.project_memberships.create!(admin_user: editor)
    assigned_org = WharePumanawa::Organization.create!(name: "Assigned org")
    assigned = assigned_org.projects.create!(name: "Keep ownership")
    records = [ project, membership, mural, contributor, mural.mural_photos.first, mural.mural_photos.first.image.attachment ]
    before = records.map { |record| record.attributes.except("organization_id") }
    unrelated = [ Resort, User, Admin::User ].map { |model| model.order(:id).map(&:attributes) }
    migration = AddWharePumanawaOrganizations.new
    migration.suppress_messages { migration.backfill_existing_projects }
    assert_equal before, records.map { |record| record.reload.attributes.except("organization_id") }
    assert_equal "existing-hosted-organization", project.organization.slug
    assert_not_equal "Whare Pūmanawa", project.organization.name
    assert_equal assigned_org, assigned.reload.organization
    assert editor.can_administer_project?(project)
    assert editor.can_view_organization?(project.organization)
    assert_equal unrelated, [ Resort, User, Admin::User ].map { |model| model.order(:id).map(&:attributes) }
    assert_empty WharePumanawa::OrganizationContributor.all
    assert_no_difference "WharePumanawa::Organization.count" do
      migration.suppress_messages { migration.backfill_existing_projects }
    end
  end

  test "no placeholder when no project requires backfill" do
    migration = AddWharePumanawaOrganizations.new
    assert_no_difference "WharePumanawa::Organization.count" do
      migration.suppress_messages { migration.backfill_existing_projects }
    end
  end
end
