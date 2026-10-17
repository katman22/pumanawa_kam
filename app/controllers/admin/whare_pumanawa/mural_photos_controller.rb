class Admin::WharePumanawa::MuralPhotosController < Admin::WharePumanawa::BaseController
  before_action :set_mural
  before_action :set_photo, only: [ :update, :destroy ]

  def create
    upload = params.require(:upload).permit(:alt_text, images: [])
    files = Array(upload[:images]).reject(&:blank?)
    saved = @mural.with_lock do
      return unless require_mural_access!(@mural)

      start = (@mural.mural_photos.maximum(:position) || -1) + 1
      photos = files.each_with_index.map do |file, index|
        @mural.mural_photos.build(image: file, alt_text: upload[:alt_text], position: start + index)
      end
      if photos.empty?
        @mural.errors.add(:base, "Choose at least one image to upload.")
        false
      elsif photos.map(&:valid?).all?
        photos.each(&:save!)
        true
      else
        photos.each { |photo| @mural.errors.add(:base, "#{photo.image.filename}: #{photo.errors.full_messages.join(', ')}") if photo.errors.any? }
        false
      end
    end
    saved ? redirect_to_mural("Photos added.") : render_mural_errors
  end

  def update
    saved = @mural.with_lock do
      return unless require_mural_access!(@mural)

      @photo.update(photo_params)
    end
    if saved
      redirect_to_mural("Photo updated.")
    else
      @mural.errors.add(:base, @photo.errors.full_messages.join(", "))
      render_mural_errors
    end
  end

  def destroy
    removed = @mural.with_lock do
      return unless require_mural_access!(@mural)

      @photo.destroy
    end
    if removed
      redirect_to_mural("Photo removed.")
    else
      @mural.errors.add(:base, @photo.errors.full_messages.join(", "))
      render_mural_errors
    end
  end

  private

  def set_mural
    @mural = ::WharePumanawa::Mural.includes(:project, mural_photos: { image_attachment: :blob }).find(params[:mural_id])
    require_mural_access!(@mural)
  end

  def set_photo
    @photo = @mural.mural_photos.find(params[:id])
  end

  def photo_params
    params.require(:whare_pumanawa_mural_photo).permit(:alt_text, :position)
  end

  def redirect_to_mural(message)
    redirect_to edit_admin_whare_pumanawa_mural_path(@mural), notice: message, status: :see_other
  end

  def render_mural_errors
    @projects = available_projects
    @photos = @mural.mural_photos.select(&:persisted?).map { |photo| photo.id == @photo&.id ? @photo : photo }
    render "admin/whare_pumanawa/murals/edit", status: :unprocessable_entity
  end
end
