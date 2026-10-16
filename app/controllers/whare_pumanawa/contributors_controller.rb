class WharePumanawa::ContributorsController < ApplicationController
  layout "whare_pumanawa"

  def show
    @contributor = WharePumanawa::Contributor.active.find_by!(slug: params[:slug])
    murals = @contributor.murals.published.ordered.includes(mural_photos: { image_attachment: :blob }).to_a
    @showcase = WharePumanawa::Showcase.new(murals)
  end
end
