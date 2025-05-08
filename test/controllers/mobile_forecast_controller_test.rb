require "test_helper"

class MobileForecastControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get mobile_forecast_index_url
    assert_response :success
  end
end
