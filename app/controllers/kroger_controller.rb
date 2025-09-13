class KrogerController < ApplicationController
  def index

  end

  def locations
    token = get_kroger_token
    service_result = ::Kroger::Location.call(zipcode: params["zipcode"], token: token)
    data = service_result.value["data"]
    @locations = data.collect { |locale| { location_id: locale["locationId"], name: locale["name"], address: locale["address"], hours: locale["hours"] } }

    render turbo_stream: [
      turbo_stream.replace(
        "location_results", partial: "locations",
        locals: { locations: @locations })
    ]
  end

  def store_selections
    @store_ids = params[:store_ids]
    render turbo_stream: [
      turbo_stream.replace(
        "location_results", partial: "product_selector",
        locals: { store_ids: @store_ids })
    ]
  end

  def products
    token = get_kroger_token
    binding.pry
    result = Kroger::MultiLocationProductSearch.new(
      term: params[:term],
      location_ids: params[:store_ids],
      token: token
    ).call
    @products = result
    binding.pry
    render turbo_stream: [
      turbo_stream.replace(
        "product_results", partial: "product_results",
        locals: { products: @products })
    ]
  end

  private

  def get_kroger_token
    token_service_results = Kroger::Token.call
    token_service_results.value
  end
end
