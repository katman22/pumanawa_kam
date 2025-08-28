class User < ApplicationRecord
  has_many :identities, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_many :receipts, dependent: :destroy
  has_many :entitlement_snapshots, dependent: :destroy

  scope :active, -> { where(status: "active").where(deleted_at: nil) }

  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :role, inclusion: { in: %w[user admin] }
  validates :status, inclusion: { in: %w[active disabled] }

  def admin?
    role == "admin"
  end

  def soft_delete!
    update!(deleted_at: Time.current, status: "disabled")
  end
end
