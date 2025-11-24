# app/models/entitlement_override.rb
class EntitlementOverride < ApplicationRecord
  belongs_to :user
  scope :active_for, ->(user) {
    where(user_id: user.id)
      .where("starts_at IS NULL OR starts_at <= ?", Time.current)
      .where("ends_at   IS NULL OR ends_at   >= ?", Time.current)
  }
end
