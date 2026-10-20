class WeatherAlertObservation < ApplicationRecord
  validates :provider, :source_identifier, :content_sha256, :first_seen_at, :source_sent_at, :event, :status, :message_type, presence: true
  validates :content_sha256, format: { with: /\A[0-9a-f]{64}\z/ }

  def readonly?
    persisted?
  end
end
