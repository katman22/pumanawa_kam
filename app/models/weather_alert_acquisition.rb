class WeatherAlertAcquisition < ApplicationRecord
  # A geographic query, not a Resort-owned job. More scope kinds need a reviewed
  # provider adapter/approval, not new per-resort scheduling relationships.
  PILOT_SCOPE = "utah_wasatch_south_point".freeze

  validates :provider, inclusion: { in: [ "noaa" ] }
  validates :scope_key, presence: true, uniqueness: { scope: :provider }
  validates :enabled, inclusion: { in: [ true, false ] }
  validates :consecutive_failures, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :stable_geography

  def owns_claim?(claim, at:)
    enabled? && lease_token == claim[:token] && lock_version == claim[:version] && lease_expires_at && lease_expires_at > at
  end

  private

  def stable_geography
    if persisted? && (will_save_change_to_query? || will_save_change_to_scope_key? || will_save_change_to_provider?)
      errors.add(:query, "cannot change an existing acquisition scope; establish a new scope and coverage baseline")
    end
  end
end
