class Subscription < ApplicationRecord
  belongs_to :user

  # scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  # scope :active-ish, -> { where(status: %w[active in_grace on_hold]) }
  # scope :current_for, ->(user) { where(user_id: user.id).active_ish.not_expired }

  def active_now?
    status.in?(%w[active in_grace on_hold]) && (expires_at.nil? || expires_at > Time.current) && revoked_at.nil?
  end
end
