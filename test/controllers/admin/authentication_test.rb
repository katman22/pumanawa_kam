require "test_helper"

class AdminAuthenticationTest < ActionDispatch::IntegrationTest
  setup do
    @admin = Admin::User.create!(username: "artist", password: "a-long-test-password")
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
    @original_secrets = %w[JWT_SECRET JWT_TOKEN].to_h { |key| [ key, ENV[key] ] }
    ENV["JWT_SECRET"] = "test-only-mobile-secret"
    ENV["JWT_TOKEN"] = "test-only-weather-secret"
  end

  teardown do
    @original_secrets.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "splash is public and renders artwork and a real HTML form" do
    get admin_login_path
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "title", "Sign in · Whare Pūmanawa"
    assert_select ".entry-artwork img[alt='']", count: 1
    assert_select "label[for='username']", "Username"
    assert_select "label[for='password']", "Password"
    assert_select "input[name='username'][autocomplete='username']"
    assert_select "input[name='password'][type='password'][autocomplete='current-password']"
    assert_select "input[name='password'][value]", count: 0
    assert_select "script", count: 0
  end

  test "unauthenticated admin redirects and HTTP Basic no longer authenticates" do
    get admin_root_path
    assert_redirected_to admin_login_path(locale: :en)
    assert_nil response.headers["WWW-Authenticate"]
    get admin_root_path, headers: { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("artist", "a-long-test-password") }
    assert_redirected_to admin_login_path(locale: :en)
  end

  test "wrong unknown and inactive admins fail generically" do
    [ [ "artist", "wrong-password" ], [ "unknown", "a-long-test-password" ] ].each do |username, password|
      post admin_login_path, params: { username: username, password: password }
      assert_response :unprocessable_entity
      assert_select "[role='alert']", "Unable to sign in. Check your credentials and try again."
      assert_nil request.session[:admin_user_id]
      assert_select "input[name='password'][value]", count: 0
    end
    @admin.update!(active: false)
    sign_in
    assert_response :unprocessable_entity
    assert_select "[role='alert']", "Unable to sign in. Check your credentials and try again."
    get admin_root_path
    assert_redirected_to admin_login_path(locale: :en)
  end

  test "sign in permits dashboard access and logout clears it" do
    sign_in
    assert_redirected_to admin_root_path(locale: :en)
    assert_equal @admin.id, request.session[:admin_user_id]
    assert_nil request.session[:user_id]
    assert_nil request.session[:password]
    get admin_root_path
    assert_response :success
    assert_select "h1", "Administration"
    assert_select "a[href=?]", admin_resorts_path(locale: :en)
    delete admin_logout_path
    assert_redirected_to admin_login_path(locale: :en)
    assert_nil request.session[:admin_user_id]
    get admin_root_path
    assert_redirected_to admin_login_path(locale: :en)
  end

  test "inactive or deleted admin loses existing access" do
    sign_in
    @admin.update!(active: false)
    get admin_root_path
    assert_redirected_to admin_login_path(locale: :en)
    @admin.update!(active: true)
    sign_in
    @admin.destroy!
    get admin_root_path
    assert_redirected_to admin_login_path(locale: :en)
  end

  test "login rotates session and login and logout enforce CSRF" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get admin_login_path
    token = css_select("input[name='authenticity_token']").first["value"]
    old_session_id = request.session.id.to_s
    sign_in
    assert_response :unprocessable_entity
    sign_in(authenticity_token: token)
    assert_redirected_to admin_root_path(locale: :en)
    assert_not_equal old_session_id, request.session.id.to_s
    get admin_root_path
    assert_response :success
    token = css_select("meta[name='csrf-token']").first["content"]
    delete admin_logout_path
    assert_response :unprocessable_entity
    get admin_root_path
    assert_response :success
    delete admin_logout_path, params: { authenticity_token: token }
    assert_redirected_to admin_login_path(locale: :en)
    get admin_root_path
    assert_redirected_to admin_login_path(locale: :en)
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "excessive login attempts are limited" do
    10.times { post admin_login_path, params: { username: "artist", password: "wrong-password" } }
    sign_in
    assert_response :too_many_requests
    assert_nil request.session[:admin_user_id]
  end

  test "admin cookie cannot authenticate either API path" do
    sign_in
    get "/api/v1/home_resorts"
    assert_response :unauthorized
    assert_equal({ "error" => "Unauthorized" }, response.parsed_body)
    get "/api/v1/weather/index"
    assert_response :unauthorized
    assert_equal({ "error" => "Unauthorized" }, response.parsed_body)
  end

  test "device User creation JWT issuance and recovery remain independent" do
    assert_difference "::User.count", 1 do
      assert_no_difference "Admin::User.count" do
        post "/api/v1/auth/device", as: :json
      end
    end
    assert_response :success
    identity = response.parsed_body
    mobile = ::User.find_by!(public_id: identity.fetch("user_id"))
    assert_equal mobile.id, JwtToken.decode(identity.fetch("jwt"))[:user_id]
    assert_equal "user", mobile.role
    assert_not mobile.has_attribute?(:password_digest)
    assert_no_difference "::User.count" do
      post "/api/v1/auth/device", params: { auth: { user_id: mobile.public_id } }, as: :json
    end
    assert_response :success
    assert_equal mobile.public_id, response.parsed_body.fetch("user_id")
    get "/api/v1/home_resorts", headers: { "Authorization" => "Bearer #{identity.fetch('jwt')}" }
    assert_response :success
    assert_equal [], response.parsed_body["free_ids"]
    get admin_root_path, headers: { "Authorization" => "Bearer #{identity.fetch('jwt')}" }
    assert_redirected_to admin_login_path(locale: :en)
  end

  test "weather JWT remains accepted by its original authentication path only" do
    Api::V1::WeatherController.any_instance.stubs(:location_services).returns([ false, [], 0 ])
    token = JWT.encode({ app: "test", exp: 1.day.from_now.to_i }, ENV.fetch("JWT_TOKEN"), "HS256")
    get "/api/v1/weather/index", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :success
    assert_equal [], response.parsed_body
    get admin_root_path, headers: { "Authorization" => "Bearer #{token}" }
    assert_redirected_to admin_login_path(locale: :en)
  end

  private

  def sign_in(**extra)
    post admin_login_path, params: { username: " ARTIST ", password: "a-long-test-password" }.merge(extra)
  end
end
