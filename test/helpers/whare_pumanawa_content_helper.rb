module WharePumanawaContentHelper
  def showcase_mural(contributor, title: "Mural", position: 0, published: true, photos: 1)
    mural = contributor.murals.create!(title: title, position: position, description: "A community story told through paint.", location: "Main Street", year: 2026, client: "Community")
    photos.times do |index|
      photo = mural.mural_photos.build(alt_text: "#{title} photograph #{index + 1}", position: index)
      photo.image.attach(io: File.open(file_fixture("mural.png")), filename: "mural.png", content_type: "image/png")
      photo.save!
    end
    mural.update!(published: published)
    mural
  end
end
