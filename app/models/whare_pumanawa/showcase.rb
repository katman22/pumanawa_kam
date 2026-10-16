# A bounded, deterministic selection for an exhibition wall, not authored layout data.
class WharePumanawa::Showcase
  MAX_PHOTOS = 10
  Item = Struct.new(:mural, :photo, :orientation, :slot, keyword_init: true)

  attr_reader :items, :story

  def initialize(murals)
    rows = murals.map { |mural| [ mural, mural.mural_photos.select(&:valid?) ] }
    seen = {}
    @items = []
    # Take each mural's hero before a second pass through supporting photographs.
    depth = 0
    while items.length < MAX_PHOTOS && rows.any? { |_mural, photos| photos[depth] }
      rows.each do |mural, photos|
        photo = photos[depth]
        next unless photo && !seen[photo.image.blob.id]

        seen[photo.image.blob.id] = true
        orientation = self.class.orientation(photo.image.blob.metadata)
        slot = orientation == :landscape && items.empty? ? :feature : orientation
        items << Item.new(mural: mural, photo: photo, orientation: orientation, slot: slot)
        break if items.length == MAX_PHOTOS
      end
      depth += 1
    end
    @story = murals.find { |mural| mural.description.present? }
  end

  def size
    case items.length
    when 0..4 then :small
    when 5..6 then :medium
    when 7..8 then :large
    else :full
    end
  end

  def self.orientation(metadata)
    metadata ||= {}
    width = metadata["width"].to_f
    height = metadata["height"].to_f
    return :neutral unless width.finite? && height.finite? && width.positive? && height.positive?

    ratio = width / height
    return :landscape if ratio > 1.2
    return :portrait if ratio < 0.8

    :squareish
  end
end
