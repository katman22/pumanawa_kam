class Admin::User < ApplicationRecord
  self.table_name = "admin_users"

  has_secure_password reset_token: false
  normalizes :username, with: ->(value) { value.strip.downcase }
  validates :username, presence: true, uniqueness: true
  validates :active, inclusion: { in: [ true, false ] }
  validates :password, length: { minimum: 12 }, allow_nil: true
end
