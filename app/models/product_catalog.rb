class ProductCatalog < ApplicationRecord
  scope :active, -> { where(status: "active") }

  def self.flags_for(store_product_ids)
    rows = active.where("external_id_ios IN (?) OR external_id_android IN (?)",
                        store_product_ids, store_product_ids)
    rows.flat_map(&:feature_flags).uniq
  end

  def self.ensure_seed!(items)
    # items: [{name:, tier:, external_id_ios:, external_id_android:, feature_flags:[]}, ...]
    items.each do |attrs|
      rec = find_or_initialize_by(name: attrs[:name])
      rec.assign_attributes(attrs)
      rec.save!
    end
  end
end
