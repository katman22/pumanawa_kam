require "test_helper"

class Api::V1::CanyonTimesControllerTest < ActionDispatch::IntegrationTest
  # test "should get times" do
  #   fake_service = Minitest::Mock.new
  #   fake_service.expect(:call, success_response)
  #
  #   CottonwoodCanyons::TravelData.stub :new, ->(resort:) { fake_service } do
  #     get api_v1_canyon_times_times_path, headers: auth_headers
  #     assert_response :success
  #   end
  # end
end

def success_response
  OpenStruct.new(
    success?: true,
    value: {
      "resort": "Alta",
      "to_resort": "16",
      "from_resort": "16",
      "departure_point": "Little Cottonwood Parking Lot",
      "parking": "Parking Open",
      "weather": ": ,  ,  @ ",
      "traffic": "Construction on SR-210 near Tanners Flat Campground — Traffic Notice: Expect one-way traffic with temporary signals through the construction area.",
      "updated_at": "Sat  7:35"
    })
end
