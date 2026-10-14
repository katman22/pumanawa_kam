require "test_helper"

class WharePumanawa::MuralPhotoTest < ActiveSupport::TestCase
  test "photo belongs to a mural and exposes an image attachment" do
    assert_not WharePumanawa::MuralPhoto.new.valid?
    mural = WharePumanawa::Mural.create!(title: "Parent")
    photo = mural.mural_photos.create!
    assert_equal mural, photo.mural
    assert_kind_of ActiveStorage::Attached::One, photo.image
    assert_not photo.image.attached?
  end

  test "photos order by position then id" do
    mural = WharePumanawa::Mural.create!(title: "Order")
    last = mural.mural_photos.create!(position: 4)
    first = mural.mural_photos.create!(position: 1)
    second = mural.mural_photos.create!(position: 1)
    expected = [ first.id, second.id, last.id ]
    assert_equal expected, mural.mural_photos.pluck(:id)
    assert_equal expected, WharePumanawa::MuralPhoto.ordered.pluck(:id)
  end

  test "position must be a nonnegative integer" do
    mural = WharePumanawa::Mural.create!(title: "Positions")
    [ -1, nil, 0.5 ].each { |position| assert_not mural.mural_photos.build(position: position).valid? }
  end

  test "drafts may be incomplete but public photos require image and alt text" do
    mural = WharePumanawa::Mural.create!(title: "Draft")
    photo = mural.mural_photos.create!
    assert photo.valid?
    mural.published = true
    assert_not photo.valid?
    assert photo.errors[:alt_text].present?
    assert photo.errors[:image].present?
    photo.alt_text = "WharePumanawa::Mural on a brick wall"
    photo.image.attach(io: File.open(file_fixture("mural.png")), filename: "mural.png", content_type: "image/png")
    assert photo.valid?
  end

  test "image association retains originals and defines vips-compatible variants" do
    photo = WharePumanawa::Mural.create!(title: "Image").mural_photos.create!(alt_text: "A mural")
    photo.image.attach(io: File.open(file_fixture("mural.png")), filename: "mural.png", content_type: "image/png")
    assert photo.reload.image.attached?
    assert_equal "image/png", photo.image.blob.content_type
    assert photo.image.variant(:thumbnail)
    assert photo.image.variant(:hero)
    assert_equal :vips, Rails.application.config.active_storage.variant_processor
  end

  test "thumbnail and hero variants process and preserve the original" do
    photo = WharePumanawa::Mural.create!(title: "Processed image").mural_photos.create!(alt_text: "Colorful landscape mural")
    original = File.binread(file_fixture("mural.png"))
    photo.image.attach(io: StringIO.new(original), filename: "mural.png", content_type: "image/png")

    thumbnail = photo.image.variant(:thumbnail).processed
    hero = photo.image.variant(:hero).processed
    thumbnail_image = Vips::Image.new_from_buffer(thumbnail.download, "")
    hero_image = Vips::Image.new_from_buffer(hero.download, "")

    assert_equal [ 240, 180 ], [ thumbnail_image.width, thumbnail_image.height ]
    assert_equal [ 1600, 1000 ], [ hero_image.width, hero_image.height ]
    assert_equal original, photo.image.download
    assert_equal thumbnail.download, photo.image.variant(:thumbnail).processed.download
    assert_equal hero.download, photo.image.variant(:hero).processed.download
  end

  test "non-image files are rejected" do
    photo = WharePumanawa::Mural.create!(title: "File Type").mural_photos.new
    photo.image.attach(io: StringIO.new("not an image"), filename: "document.pdf", content_type: "application/pdf")
    assert_not photo.valid?
    assert photo.errors[:image].present?
  end

  test "database requires parent position and a valid foreign key" do
    mural = WharePumanawa::Mural.create!(title: "Constraint")
    assert_raises(ActiveRecord::NotNullViolation) do
      WharePumanawa::MuralPhoto.transaction(requires_new: true) { WharePumanawa::MuralPhoto.insert_all!([ { mural_id: nil } ]) }
    end
    assert_raises(ActiveRecord::NotNullViolation) do
      WharePumanawa::MuralPhoto.transaction(requires_new: true) { WharePumanawa::MuralPhoto.insert_all!([ { mural_id: mural.id, position: nil } ]) }
    end
    assert_raises(ActiveRecord::InvalidForeignKey) do
      WharePumanawa::MuralPhoto.transaction(requires_new: true) { WharePumanawa::MuralPhoto.insert_all!([ { mural_id: -1 } ]) }
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      WharePumanawa::MuralPhoto.transaction(requires_new: true) { WharePumanawa::MuralPhoto.insert_all!([ { mural_id: mural.id, position: -1 } ]) }
    end
  end
end
