class WharePumanawa::OrganizationsController < ApplicationController
  layout "whare_pumanawa"

  def index
    @organizations = WharePumanawa::Organization.active.ordered
  end

  def show
    @organization = WharePumanawa::Organization.active.find_by!(slug: params[:slug])
    # Project active state is organizational, not a new publication rule.
    owned_projects = @organization.projects
    murals = WharePumanawa::Mural.published.where(project_id: owned_projects.select(:id))
      .ordered.includes(mural_photos: { image_attachment: :blob }).to_a
    @projects = owned_projects.where(id: murals.map(&:project_id)).ordered
    @contributors = @organization.contributors.active.ordered
    @showcase = WharePumanawa::Showcase.new(murals)
  end
end
