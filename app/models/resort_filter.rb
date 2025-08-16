# app/models/resort.rb
# app/models/resort_filter.rb
class ResortFilter < ApplicationRecord
  KINDS = %w[roadway event alerts camera].freeze

  belongs_to :resort
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :data, presence: true

  scope :by_kind, ->(k) { where(kind: k.to_s) }
end

