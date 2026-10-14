class WharePumanawa::MuralsController < ApplicationController
  layout "whare_pumanawa"
  before_action :load_murals

  def index
    @mural = @murals.first
    load_photos
  end

  def show
    @mural = @murals.find { |mural| mural.slug == params[:slug] }
    raise ActiveRecord::RecordNotFound unless @mural

    load_photos
  end

  private

  def load_murals
    @murals = WharePumanawa::Mural.published.ordered
      .includes(mural_photos: { image_attachment: :blob }).to_a
  end

  def load_photos
    # Recheck publication-facing validity if an attachment was removed separately.
    @photos = @mural ? @mural.mural_photos.select(&:valid?) : []
  end
end
