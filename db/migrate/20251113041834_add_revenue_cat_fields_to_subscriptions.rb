class AddRevenueCatFieldsToSubscriptions < ActiveRecord::Migration[7.2]
  def change
    add_column :subscriptions, :purchased_at, :datetime
    add_column :subscriptions, :will_renew, :boolean
    add_column :subscriptions, :source, :string, default: "revenue_cat", null: false
  end
end
