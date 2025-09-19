# Input: provider: "google"|"apple", id_token: "..." (or apple identity token)
# Output: ServiceResult(user)
class Oauth::LinkOrCreateUser < ApplicationService
  def initialize(provider:, id_token:)
    @provider = provider
    @id_token = id_token
  end

  def call
    verified = case @provider
    when "google" then Oauth::Verify::Google.call!(id_token: @id_token).value
    when "apple"  then Oauth::Verify::Apple.call!(id_token: @id_token).value
    else return failed("Unsupported provider")
    end
    # verified: { uid:, email:, display_name:, raw: {...} }

    identity = Identity.find_by(provider: @provider, uid: verified[:uid])
    user = identity&.user

    if user.nil?
      # Try to attach to existing user by email if present & unique
      user = verified[:email].present? ? User.find_by(email: verified[:email]) : nil
      user ||= User.create!(
        email: verified[:email],
        display_name: verified[:display_name],
        last_sign_in_at: Time.current
      )
      Identity.create!(
        user: user, provider: @provider, uid: verified[:uid], email: verified[:email], raw: verified[:raw] || {}
      )
    else
      # Update provider email/name if changed
      identity.update!(email: verified[:email]) if verified[:email].present? && identity.email != verified[:email]
      # Optionally backfill display_name if missing
      if user.display_name.blank? && verified[:display_name].present?
        user.update!(display_name: verified[:display_name])
      end
      user.update!(last_sign_in_at: Time.current)
    end

    successful(user)
  end
end
