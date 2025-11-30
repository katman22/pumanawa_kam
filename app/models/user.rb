class User < ApplicationRecord
  has_many :identities, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_many :receipts, dependent: :destroy
  has_many :entitlement_snapshots, dependent: :destroy
  has_many :entitlement_overrides, dependent: :destroy

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

  # Returns the currently-active override, or nil
  def active_entitlement_override
    entitlement_overrides
      .where("starts_at IS NULL OR starts_at <= ?", Time.current)
      .where("ends_at   IS NULL OR ends_at   >  ?", Time.current)
      .order(Arel.sql("ends_at IS NULL DESC"), starts_at: :desc)
      .first
  end

end
