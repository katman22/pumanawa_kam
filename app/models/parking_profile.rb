class ParkingProfile < ApplicationRecord
  belongs_to :resort

  scope :active_on, ->(date) { where("effective_from IS NULL OR effective_from <= ?", date)
                                 .where("effective_to IS NULL OR effective_to >= ?", date) }
end
