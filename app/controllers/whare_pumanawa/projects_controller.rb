class WharePumanawa::ProjectsController < ApplicationController
  layout "whare_pumanawa"

  def show
    @project = WharePumanawa::Project.joins(:organization).merge(WharePumanawa::Organization.active)
      .includes(:organization).find_by!(slug: params[:slug])
    @organization = @project.organization
    # Project active state remains organizational; mural publication is authoritative.
    murals = @project.murals.published.ordered.includes(mural_photos: { image_attachment: :blob }).to_a
    @showcase = WharePumanawa::Showcase.new(murals)
  end
end
