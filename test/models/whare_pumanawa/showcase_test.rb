require "test_helper"
require_relative "../../helpers/whare_pumanawa_content_helper"

class WharePumanawa::ShowcaseTest < ActiveSupport::TestCase
  include WharePumanawaContentHelper

  test "metadata classifies orientations with a safe missing metadata fallback" do
    assert_equal :landscape, WharePumanawa::Showcase.orientation({ "width" => 2000, "height" => 1000 })
    assert_equal :portrait, WharePumanawa::Showcase.orientation({ "width" => 800, "height" => 1600 })
    assert_equal :squareish, WharePumanawa::Showcase.orientation({ "width" => 1000, "height" => 1050 })
    [ nil, {}, { "width" => 200 }, { "width" => 0, "height" => 10 }, { "width" => "bad", "height" => 10 } ].each do |metadata|
      assert_equal :neutral, WharePumanawa::Showcase.orientation(metadata)
    end
  end

  test "selection prefers each mural hero before supporting photos and does not repeat blobs" do
    owner = WharePumanawa::Contributor.create!(name: "Artist")
    first = showcase_mural(owner, title: "First", photos: 3)
    second = showcase_mural(owner, title: "Second", photos: 2)
    second.mural_photos.create!(alt_text: "Shared original", position: 3, image: first.mural_photos.first.image.blob)
    wall = WharePumanawa::Showcase.new(owner.murals.ordered.includes(mural_photos: { image_attachment: :blob }).to_a)
    assert_equal [ first.id, second.id ], wall.items.first(2).map { |item| item.mural.id }
    assert_equal 5, wall.items.length
    blob_ids = wall.items.map { |item| item.photo.image.blob.id }
    assert_equal blob_ids.uniq, blob_ids
    assert_equal first, wall.story
  end

  test "sizes are bounded and deterministic across the four compositions" do
    owner = WharePumanawa::Contributor.create!(name: "Artist")
    [ [ 4, :small ], [ 6, :medium ], [ 8, :large ], [ 12, :full ] ].each do |count, size|
      mural = showcase_mural(owner, title: "Composition #{count}", photos: count)
      wall = WharePumanawa::Showcase.new([ mural ])
      assert_equal size, wall.size
      assert_equal [ count, 10 ].min, wall.items.length
      assert_equal wall.items.map(&:photo), WharePumanawa::Showcase.new([ mural ]).items.map(&:photo)
    end
  end
end
