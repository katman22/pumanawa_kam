require "test_helper"

class KaingaControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get kainga_index_url
    assert_response :success
  end
end
