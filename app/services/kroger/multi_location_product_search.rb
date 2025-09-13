module Kroger
  class MultiLocationProductSearch
    attr_reader :term, :location_ids, :token, :limit

    def initialize(term:, location_ids:, token:, limit: 5)
      @term = term
      @location_ids = Array(location_ids)
      @token = token
      @limit = limit
    end

    def call
      location_ids.flat_map do |location_id|
        result = Kroger::Product.new(
          term: term,
          location_id: location_id,
          token: token,
          limit: limit
        ).call

        if result.success?
          products = result.value["data"]
          products.map { |product| product.merge("location_id" => location_id) }
        else
          []
        end
      end
    end
  end
end
