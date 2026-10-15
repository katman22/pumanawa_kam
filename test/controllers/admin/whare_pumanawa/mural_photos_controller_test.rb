require "test_helper"

class Admin::WharePumanawa::MuralPhotosControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    admin = Admin::User.create!(username: "artist", password: "a-long-test-password", role: :mural_admin)
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
    post admin_login_path, params: { username: admin.username, password: "a-long-test-password" }
    @mural = ::WharePumanawa::Mural.create!(title: "Photos")
  end

  test "multiple real images upload then alt text and ordering can change" do
    assert_difference "WharePumanawa::MuralPhoto.count", 2 do
      post admin_whare_pumanawa_mural_mural_photos_path(@mural), params: { upload: { images: [ image, image ], alt_text: "Mural details" } }
    end
    assert_redirected_to edit_admin_whare_pumanawa_mural_path(@mural, locale: :en)
    first, second = @mural.mural_photos.to_a
    assert_equal [ 0, 1 ], [ first.position, second.position ]
    patch admin_whare_pumanawa_mural_mural_photo_path(@mural, second), params: { whare_pumanawa_mural_photo: { alt_text: "Blue paint detail", position: 0 } }
    patch admin_whare_pumanawa_mural_mural_photo_path(@mural, first), params: { whare_pumanawa_mural_photo: { position: 3 } }
    assert_equal second, @mural.mural_photos.reload.first
    assert_equal "Blue paint detail", second.reload.alt_text
    variant = second.image.variant(:thumbnail).processed
    decoded = Vips::Image.new_from_buffer(variant.download, "")
    assert_equal [ 240, 180 ], [ decoded.width, decoded.height ]
    get edit_admin_whare_pumanawa_mural_path(@mural)
    assert_response :success
    assert_select "h3", text: /Hero \/ thumbnail/
    assert_select "form[enctype='multipart/form-data']"
  end

  test "invalid image batch is rejected without persisting valid siblings" do
    invalid = Rack::Test::UploadedFile.new(file_fixture("mural-small.jpg"), "application/pdf", original_filename: "document.pdf")
    # A genuine PDF signature ensures content identification rejects it.
    invalid.tempfile.rewind
    invalid.tempfile.truncate(0)
    invalid.tempfile.write("%PDF-1.4\nnot an image")
    invalid.tempfile.rewind
    assert_no_difference "WharePumanawa::MuralPhoto.count" do
      post admin_whare_pumanawa_mural_mural_photos_path(@mural), params: { upload: { images: [ image, invalid ] } }
    end
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /JPEG, PNG, or WebP/
  end

  test "published photo alt text is enforced and last photo requires unpublishing" do
    post admin_whare_pumanawa_mural_mural_photos_path(@mural), params: { upload: { images: [ image ], alt_text: "Heron mural" } }
    photo = @mural.mural_photos.first
    @mural.update!(published: true)
    patch admin_whare_pumanawa_mural_mural_photo_path(@mural, photo), params: { whare_pumanawa_mural_photo: { alt_text: " " } }
    assert_response :unprocessable_entity
    assert_equal "Heron mural", photo.reload.alt_text
    delete admin_whare_pumanawa_mural_mural_photo_path(@mural, photo)
    assert_response :unprocessable_entity
    assert photo.reload.persisted?
    assert_select "[role=alert]", text: /Unpublish/
  end

  test "removal purges actual attachment bytes and mural deletion cleans owned photos" do
    post admin_whare_pumanawa_mural_mural_photos_path(@mural), params: { upload: { images: [ image ] } }
    photo = @mural.mural_photos.first
    blob = photo.image.blob
    assert blob.download.present?
    perform_enqueued_jobs(only: ActiveStorage::PurgeJob) do
      delete admin_whare_pumanawa_mural_mural_photo_path(@mural, photo)
    end
    assert_not ::WharePumanawa::MuralPhoto.exists?(photo.id)
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_raises(ActiveStorage::FileNotFoundError) { blob.download }
    post admin_whare_pumanawa_mural_mural_photos_path(@mural), params: { upload: { images: [ image ], alt_text: "Public photo" } }
    @mural.update!(published: true)
    assert_difference "WharePumanawa::MuralPhoto.count", -1 do
      delete admin_whare_pumanawa_mural_path(@mural)
    end
  end

  test "nested photo IDs cannot target a different mural" do
    other = ::WharePumanawa::Mural.create!(title: "Other")
    photo = other.mural_photos.create!
    patch admin_whare_pumanawa_mural_mural_photo_path(@mural, photo), params: { whare_pumanawa_mural_photo: { position: 4 } }
    assert_response :not_found
    assert_equal 0, photo.reload.position
  end

  test "published murals can remove a supporting photo while retaining a valid hero" do
    post admin_whare_pumanawa_mural_mural_photos_path(@mural), params: { upload: { images: [ image, image ], alt_text: "Heron mural" } }
    @mural.update!(published: true)
    first, second = @mural.mural_photos.to_a
    assert_difference "WharePumanawa::MuralPhoto.count", -1 do
      delete admin_whare_pumanawa_mural_mural_photo_path(@mural, second)
    end
    assert_response :see_other
    assert_equal first, @mural.mural_photos.reload.first
    assert @mural.reload.valid?
  end

  private

  def image
    Rack::Test::UploadedFile.new(file_fixture("mural-small.jpg"), "image/jpeg")
  end
end
