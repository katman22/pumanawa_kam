# app/models/home_resort_change_window.rb
class HomeResortChangeWindow < ApplicationRecord
  belongs_to :user
  validates :window_start, presence: true
end
