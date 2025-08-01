# # frozen_string_literal: true
#
# require "test_helper"
#
# module CottonwoodCanyons
#   module Google
#     class DirectionsTest < ActiveSupport::TestCase
#       def setup
#         @origin = "Big Cottonwood Canyon, UT"
#         @destination = "Brighton Resort, UT"
#         @service = Directions.new(origin: @origin, destination: @destination)
#       end
#
#       test "returns successful result with routes" do
#         mock_response = Minitest::Mock.new
#         mock_body = {
#           status: "OK",
#           routes: [ { summary: "Test Route", legs: [] } ]
#         }.to_json
#
#         mock_response.expect :nil?, false
#         mock_response.expect :[], nil, [ "status" ]
#         mock_response.expect :body, mock_body
#
#         Directions.any_instance.stubs(:google_directions).returns(mock_response)
#         result = @service.call
#         assert_kind_of ServiceResult, result
#         assert_equal "Test Route", result&.value&.first["summary"]
#       end
#
#       test "returns nil for nil response" do
#         Directions.any_instance.stubs(:google_directions).returns(nil)
#         result = @service.call
#         assert_nil result
#       end
#
#       test "returns nil for status 404" do
#         mock_response = Minitest::Mock.new
#         mock_response.expect :nil?, false
#         mock_response.expect :[], 404, [ "status" ]
#
#         Directions.any_instance.stubs(:google_directions).returns(mock_response)
#
#         result = @service.call
#         assert_nil result
#       end
#
#       test "logs error and returns failed result if exception is raised" do
#         Directions.any_instance.stubs(:google_directions).raises(StandardError.new("Something went wrong"))
#         Rails.logger.expects(:error).with(regexp_matches(/Google Directions Service failed: Something went wrong/))
#
#         result = @service.call
#         assert_kind_of ServiceResult, result
#         assert_match /Something went wrong/, result&.value
#       end
#     end
#   end
# end
