class WharePumanawa::OrganizationContributor < ApplicationRecord
  belongs_to :organization, inverse_of: :organization_contributors
  belongs_to :contributor, inverse_of: :organization_contributors

  validates :contributor_id, uniqueness: { scope: :organization_id }
end
