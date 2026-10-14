require "test_helper"

class AdminIntegrationBoundariesTest < ActionDispatch::IntegrationTest
  setup do
    @original_secret = ENV["JWT_SECRET"]
    ENV["JWT_SECRET"] = "test-only-boundary-secret"
    Admin::SessionsController::LOGIN_ATTEMPTS.clear
  end

  teardown do
    @original_secret.nil? ? ENV.delete("JWT_SECRET") : ENV["JWT_SECRET"] = @original_secret
  end

  test "existing public roots and admin resource routes are unchanged" do
    {
      "www.auraweatherforecasts.com" => "kainga",
      "www.canyontraveller.com" => "canyon_traveller",
      "www.canyontravellers.com" => "canyon_traveller",
      "example.com" => "kainga"
    }.each do |host, controller|
      route = Rails.application.routes.recognize_path("https://#{host}/", method: :get)
      assert_equal controller, route[:controller]
      assert_equal "index", route[:action]
    end
    {
      "/admin/resorts" => "admin/resorts",
      "/admin/resorts/1/cameras" => "admin/cameras",
      "/admin/resort_filters/1/edit" => "admin/resort_filters",
      "/admin/parking_profiles/1/2026-27/edit" => "admin/parking_profiles"
    }.each do |path, controller|
      assert_equal controller, Rails.application.routes.recognize_path(path, method: :get)[:controller]
    end
  end

  test "admin login does not change mobile subscription entitlement or home resort ownership" do
    mobile = ::User.create!
    other_mobile = ::User.create!
    resort = Resort.create!(resort_name: "Boundary Resort", slug: "boundary-resort", latitude: 40.6, longitude: -111.6)
    HomeResort.create!(user: mobile, resort: resort, kind: 0)
    subscription = mobile.subscriptions.create!(platform: "ios", product_id: "test.pro", status: "active", expires_at: 1.day.from_now)
    mobile.entitlement_snapshots.create!(active: true, tier: "pro", version: 2, features: [ "test-feature" ], source: {})
    admin = Admin::User.create!(username: "operator", password: "a-long-test-password")
    token = JwtToken.issue({ user_id: mobile.id })
    headers = { "Authorization" => "Bearer #{token}" }

    get "/api/v1/entitlements/index", headers: headers
    assert_response :success
    expected_entitlements = response.parsed_body
    assert_equal "pro", expected_entitlements["tier"]
    assert_equal true, expected_entitlements["active"]
    get "/api/v1/home_resorts", headers: headers
    assert_response :success
    expected_home_resorts = response.parsed_body
    assert_includes expected_home_resorts["subscribed_ids"], resort.slug

    assert_no_difference [ "::User.count", "Subscription.count", "EntitlementSnapshot.count", "HomeResort.count" ] do
      post admin_login_path, params: { username: admin.username, password: "a-long-test-password" }
    end
    get "/api/v1/entitlements/index", headers: headers
    assert_response :success
    assert_equal expected_entitlements, response.parsed_body
    get "/api/v1/home_resorts", headers: headers
    assert_response :success
    assert_equal expected_home_resorts, response.parsed_body
    assert subscription.reload.active_now?
    assert_equal [ subscription.id ], Subscription.current_for(mobile).pluck(:id)
    assert_empty Subscription.current_for(other_mobile)

    get "/api/v1/home_resorts", headers: { "Authorization" => "Bearer #{JwtToken.issue({ user_id: other_mobile.id })}" }
    assert_response :success
    assert_empty response.parsed_body["subscribed_ids"]
  end
end
