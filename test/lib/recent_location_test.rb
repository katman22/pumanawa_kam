require "test_helper"

class RecentLocationsTest < ActiveSupport::TestCase
  def setup
    @session = {}
    @recent_locations = RecentLocations.new({})
  end

  test "it creates new blank recent locations" do
    assert_equal [], @recent_locations.list
  end

  test "it tracks recent locations search" do
    new_location = {name: "Wellington"}
    @recent_locations.add(new_location)
    assert_equal [new_location], @recent_locations.list
  end

  test "it adds new location to start list" do
    new_location = {name: "Wellington"}
    @recent_locations.add(new_location)
    additional_location = {name: "Taupo"}
    @recent_locations.add(additional_location)
    assert_equal [additional_location, new_location], @recent_locations.list
  end

  test "it removes duplicates from list" do
    new_location = {name: "Wellington"}
    @recent_locations.add(new_location)
    additional_location = {name: "Taupo"}
    @recent_locations.add(additional_location)
    @recent_locations.add(new_location)
    assert_equal [new_location, additional_location], @recent_locations.list
  end

end
