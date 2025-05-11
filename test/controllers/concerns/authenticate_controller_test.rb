require "test_helper"


class AuthenticateController < ActionController::API
  include AuthenticateApi

  def test_action
    auth_header = request.headers["Authorization"]
  end
end

class AuthenticateControllerTest < ActionDispatch::IntegrationTest
  test "will get index" do

  end
end
