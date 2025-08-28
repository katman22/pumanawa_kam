# app/presenters/resort_context_presenter.rb
class ResortContextPresenter
  def initialize(resort)
    @resort = resort
  end

  def as_json
    {
      resort_name: @resort.resort_name,
      departure_point: @resort.departure_point,
      latitude: @resort.latitude,
      longitude: @resort.longitude,
      location: @resort.resort_name,
      roadway_filter: @resort.filter_data(:roadway),
      event: @resort.filter_data(:event),
      alerts: @resort.filter_data(:alerts),
      camera: @resort.filter_data(:camera)
    }
  end

  def as_resorts
    {
      id: @resort.id,
      resort_id: @resort.slug,
      resort_name: @resort.resort_name,
      departure_point: @resort.departure_point,
      latitude: @resort.latitude,
      longitude: @resort.longitude,
      location: @resort.location
    }
  end

end
