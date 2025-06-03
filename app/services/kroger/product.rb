module Kroger
  class Product < Base
    attr_reader :term, :location_id, :limit

    FILTER_INPUT = ->(term, location_id, limit) {
      "products?filter.term=#{CGI.escape(term)}&filter.locationId=#{location_id}&filter.limit=#{limit}"
    }

    def initialize(term:, location_id:, token:, limit: 5)
      super(token: token)
      @term = term
      @location_id = location_id
      @limit = limit
    end

    def call
      uri = URI("#{BASE_URL}/#{FILTER_INPUT.call(term, location_id, limit)}")
      response = get(uri)
      response[:success] ? successful(response[:data]) : failed(response)
    end
  end
end
