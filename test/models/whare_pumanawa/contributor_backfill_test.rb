require "test_helper"
require Rails.root.join("db/migrate/20261016000001_add_whare_pumanawa_contributors")
require_relative "../../helpers/whare_pumanawa_content_helper"

class WharePumanawa::ContributorBackfillTest < ActiveSupport::TestCase
  include WharePumanawaContentHelper

  test "real migration backfill preserves existing published content and existing assignments" do
    owner = WharePumanawa::Contributor.create!(name: "Existing owner")
    mural = showcase_mural(owner, title: "Live mural")
    mural.update_columns(contributor_id: nil)
    before = mural.reload.attributes.except("contributor_id")
    attachment_ids = mural.mural_photos.first.image.attachment.attributes
    assigned = owner.murals.create!(title: "Already assigned")
    migration = AddWharePumanawaContributors.new
    migration.suppress_messages { migration.backfill_existing_murals }
    assert_equal before, mural.reload.attributes.except("contributor_id")
    assert_equal "whare-pumanawa", mural.contributor.slug
    assert_equal "Whare Pūmanawa", mural.contributor.name
    assert_equal attachment_ids, mural.mural_photos.first.image.attachment.attributes
    assert_equal owner.id, assigned.reload.contributor_id
    assert_no_difference "WharePumanawa::Contributor.count" do
      migration.suppress_messages { migration.backfill_existing_murals }
    end
  end
end
