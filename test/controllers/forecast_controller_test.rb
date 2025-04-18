require "test_helper"

class ForecastControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get forecast_index_url
    assert_response :success
  end

  test "should get full" do
    get forecast_full_url
    assert_response :success
  end

  test "should get text" do
    get forecast_text_url
    assert_response :success
  end
end
