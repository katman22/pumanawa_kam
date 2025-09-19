# app/services/oauth/verify/apple.rb
class Oauth::Verify::Apple < ApplicationService
  def initialize(id_token:); @id_token = id_token; end
  def call
    # TODO: verify Apple identity token (JWT) with Apple public keys & your client_id (bundle id)
    successful({
                 uid: "apple-sub-abc",
                 email: "random@privaterelay.appleid.com", # may be nil depending on scopes
                 display_name: nil,
                 raw: { "token" => "..." }
               })
  end
end
