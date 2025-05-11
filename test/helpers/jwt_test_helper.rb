# frozen_string_literal: true

module JwtTestHelper
  def generate_jwt_token
    payload = { app: "test_client", exp: 1.day.from_now.to_i }
    JWT.encode(payload, ENV["JWT_SECRET"] || "test_secret_key", "HS256")
  end

  def auth_headers
    {
      "Authorization" => "Bearer #{generate_jwt_token}",
      "Content-Type" => "application/json"
    }
  end

  def erred_auth_headers
    {
      "Authorization" => "Bearer bad_token",
      "Content-Type" => "application/json"
    }
  end
end
