require "test_helper"
require Rails.root.join("db/migrate/20261016000002_add_whare_pumanawa_projects")
require_relative "../../helpers/whare_pumanawa_content_helper"

class WharePumanawa::ProjectBackfillTest < ActiveSupport::TestCase
  include WharePumanawaContentHelper

  test "backfill preserves existing content attribution attachments and assigned projects" do
    contributor = WharePumanawa::Contributor.create!(name: "Artist")
    mural = showcase_mural(contributor)
    before = mural.reload.attributes.except("project_id")
    photo = mural.mural_photos.first
    attachment = photo.image.attachment.attributes
    project = WharePumanawa::Project.create!(name: "Already assigned")
    assigned = project.murals.create!(title: "Keep assignment")
    editor = Admin::User.create!(username: "existing-artist", password: "a-long-test-password", role: :mural_admin)
    owner = Admin::User.create!(username: "owner", password: "a-long-test-password", role: :super_admin)
    canyon = Admin::User.create!(username: "canyon", password: "a-long-test-password", role: :canyon_admin)
    migration = AddWharePumanawaProjects.new
    migration.suppress_messages do
      migration.backfill_existing_murals
      migration.grant_initial_memberships
    end
    assert_equal before, mural.reload.attributes.except("project_id")
    assert_equal "whare-pumanawa-collection", mural.project.slug
    assert_equal attachment, photo.reload.image.attachment.attributes
    assert_equal project.id, assigned.reload.project_id
    assert editor.can_administer_mural?(mural)
    assert_not editor.can_administer_project?(project)
    assert_empty owner.project_memberships
    assert_empty canyon.project_memberships
    assert_no_difference [ "WharePumanawa::Project.count", "WharePumanawa::ProjectMembership.count" ] do
      migration.suppress_messages do
        migration.backfill_existing_murals
        migration.grant_initial_memberships
      end
    end
    future = Admin::User.create!(username: "future", password: "a-long-test-password", role: :mural_admin)
    assert_empty future.project_memberships
  end

  test "empty database does not gain an invented collection or membership" do
    Admin::User.create!(username: "artist", password: "a-long-test-password", role: :mural_admin)
    migration = AddWharePumanawaProjects.new
    assert_no_difference [ "WharePumanawa::Project.count", "WharePumanawa::ProjectMembership.count" ] do
      migration.suppress_messages do
        migration.backfill_existing_murals
        migration.grant_initial_memberships
      end
    end
  end
end
