module Kroger
  class Location < Base
    attr_reader :zipcode, :limit

    ZIP_QUERY = ->(zipcode, limit) { "locations?filter.zipCode.near=#{zipcode}&filter.limit=#{limit}" }

    def initialize(zipcode:, token:, limit: 5)
      super(token: token)
      @zipcode = zipcode
      @limit = limit
    end

    def call
      uri = URI("#{BASE_URL}/#{ZIP_QUERY.call(zipcode, limit)}")
      response = get(uri)
      response[:success] ? successful(response[:data]) : failed(response)
    end
  end
end
