require "test_helper"

class WharePumanawa::ImagePolicyTest < ActiveSupport::TestCase
  test "namespace tables and polymorphic attachment record type are correct" do
    assert_equal "whare_pumanawa_murals", WharePumanawa::Mural.table_name
    assert_equal "whare_pumanawa_mural_photos", WharePumanawa::MuralPhoto.table_name
    assert_not Object.const_defined?(:Mural, false)
    assert_not Object.const_defined?(:MuralPhoto, false)
    photo = WharePumanawa::Mural.create!(title: "Namespace").mural_photos.create!
    photo.image.attach(io: File.open(file_fixture("mural.png")), filename: "mural.png")
    attachment = photo.reload.image.attachment
    assert_equal "WharePumanawa::MuralPhoto", attachment.record_type
    assert_kind_of WharePumanawa::MuralPhoto, attachment.reload.record
    assert_equal "test", attachment.blob.service_name
  end

  test "JPEG PNG and WebP originals process with no hero upscaling" do
    mural = WharePumanawa::Mural.create!(title: "Formats")
    { "mural.png" => [ 1600, 1000 ], "mural-small.jpg" => [ 40, 25 ], "mural-small.webp" => [ 40, 25 ] }.each do |filename, dimensions|
      photo = mural.mural_photos.create!
      original = File.binread(file_fixture(filename))
      photo.image.attach(io: StringIO.new(original), filename: filename)
      assert photo.valid?, photo.errors.full_messages.join(", ")
      processed = photo.image.variant(:hero).processed
      image = Vips::Image.new_from_buffer(processed.download, "")
      assert_equal dimensions, [ image.width, image.height ]
      assert_equal original, photo.image.download
    end
  end

  test "size limit allows 20 MiB and rejects larger attached content" do
    photo = WharePumanawa::Mural.create!(title: "Size").mural_photos.create!
    png = File.binread(file_fixture("mural.png"))
    at_limit = png + ("x" * (20.megabytes - png.bytesize))
    photo.image.attach(io: StringIO.new(at_limit), filename: "mural.png", content_type: "image/png")
    assert photo.valid?
    photo.image.attach(io: StringIO.new(at_limit + "x"), filename: "mural.png", content_type: "image/png")
    assert_not photo.valid?
    assert photo.errors[:image].present?
  end

  test "public photos cannot have blank alt text and drafts can be incomplete" do
    mural = WharePumanawa::Mural.create!(title: "Alt text")
    photo = mural.mural_photos.create!(alt_text: " ")
    assert photo.valid?
    photo.image.attach(io: File.open(file_fixture("mural.png")), filename: "mural.png")
    assert_not mural.update(published: true)
    assert photo.errors[:alt_text].present?
  end

  test "destroying a mural destroys its owned photos and attachment records" do
    mural = WharePumanawa::Mural.create!(title: "Cleanup")
    photo = mural.mural_photos.create!
    photo.image.attach(io: File.open(file_fixture("mural.png")), filename: "mural.png")
    attachment_id = photo.image.attachment.id
    mural.destroy!
    assert_not WharePumanawa::MuralPhoto.exists?(photo.id)
    assert_not ActiveStorage::Attachment.exists?(attachment_id)
  end

  test "production image service is explicit and does not fall back to web disk" do
    selector = WharePumanawa::MuralPhoto.reflect_on_attachment(:image).options.fetch(:service_name)
    assert_equal :test, selector.call(nil)
    Rails.env.stub(:production?, true) do
      assert_equal :mural_artwork, selector.call(nil)
    end
  end
end
