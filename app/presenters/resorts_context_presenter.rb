# app/presenters/resort_context_presenter.rb
class ResortsContextPresenter
  def initialize(resorts)
    @resorts = resorts
  end

  def all_resorts
    @resorts.collect do |resort|
      ResortContextPresenter.new(resort).as_resorts
    end
  end

end
