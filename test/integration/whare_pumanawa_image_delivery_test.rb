require "test_helper"

class WharePumanawaImageDeliveryTest < ActionDispatch::IntegrationTest
  test "generated thumbnail and hero are served through Active Storage" do
    photo = WharePumanawa::Mural.create!(title: "Image delivery").mural_photos.create!(alt_text: "Colorful landscape mural")
    photo.image.attach(io: File.open(file_fixture("mural.png")), filename: "mural.png", content_type: "image/png")

    { thumbnail: [ 240, 180 ], hero: [ 1600, 1000 ] }.each do |name, dimensions|
      variant = photo.image.variant(name).processed
      get rails_representation_path(variant, only_path: true)
      assert_response :redirect
      follow_redirect!
      assert_response :success
      assert_equal "image/png", response.media_type
      image = Vips::Image.new_from_buffer(response.body, "")
      assert_equal dimensions, [ image.width, image.height ]
    end
  end
end
