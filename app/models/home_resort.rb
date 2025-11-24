class HomeResort < ApplicationRecord
  belongs_to :user
  belongs_to :resort

  enum :kind, { subscribed: 0, free: 1 }

  validates :user_id, :resort_id, :kind, presence: true
  validates :resort_id, uniqueness: { scope: :user_id, message: "already selected for this user" }

  scope :for_user,         ->(user) { where(user_id: user.id) }
  scope :free_only,        -> { where(kind: :free) }
  scope :subscribed_only,  -> { where(kind: :subscribed) }

  def subscribed? = kind == "subscribed"

  def slug
    resort.slug
  end
end
