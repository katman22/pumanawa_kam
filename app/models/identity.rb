class Identity < ApplicationRecord
  belongs_to :user

  validates :provider, inclusion: { in: %w[google apple] }
  validates :uid, presence: true
end
