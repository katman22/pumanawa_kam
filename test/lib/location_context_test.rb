require "test_helper"

class LocationContextTest < ActiveSupport::TestCase
  def setup
    params = { location: "Wellington, New Zealand",
               location_name: "Wellington",
               lat: 41,
               long: 174 }
    @location_context = LocationContext.new(params)
  end

  test "it returns the values posted in params" do
    assert_equal @location_context.latitude.to_f, 41.to_f
    assert_equal @location_context.longitude.to_f, 174.to_f
    assert_equal @location_context.location_name, "Wellington"
    assert_equal @location_context.location, "Wellington, New Zealand"
  end
end
