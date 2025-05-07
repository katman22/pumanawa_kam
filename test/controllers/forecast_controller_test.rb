require "test_helper"

class ForecastControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    service_response = OpenStruct.new(
      success?: true,
      value: { locations: [{
                             "components" => { "postcode" => "84121" },
                             "formatted" => "Utah, United States of America",
                             "geometry" => { "lat" => 39.4225192, "lng" => -111.714358 } },
                           {
                             "components" => { "postcode" => "84121" },
                             "formatted" => "Utah County, Utah, United States of America",
                             "geometry" => { "lat" => 40.177058, "lng" => -111.6910719 } }],
               total: 2 })
    service_handler = OpenStruct.new(call: service_response)

    fake_service = Minitest::Mock.new
    fake_service.expect(:call, service_handler, ["Utah"])

    OpenCage::GeoLocation::LocationFromInput.stub :new, fake_service do
      get forecast_view_url, params: { location: "Utah" }
      assert_response :success
    end
  end

  # test "should get full" do
  #   get forecast_full_url
  #   assert_response :success
  # end
  #
  # test "should get text" do
  #   get forecast_text_only_path
  #   assert_response :success
  # end
end
