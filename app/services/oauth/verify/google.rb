# app/services/oauth/verify/google.rb
class Oauth::Verify::Google < ApplicationService
  def initialize(id_token:); @id_token = id_token; end
  def call
    # TODO: call Google tokeninfo OR verify JWT locally with Google's certs
    # Return a normalized hash:
    successful({
                 uid: "google-sub-123",
                 email: "user@example.com",
                 display_name: "Kameron",
                 raw: { "token" => "..." }
               })
  end
end
