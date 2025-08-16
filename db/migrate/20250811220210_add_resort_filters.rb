class AddResortFilters < ActiveRecord::Migration[8.0]
  def change
    create_table :resort_filters do |t|
      t.references :resort, null: false, foreign_key: true
      t.string  :kind, null: false, limit: 32 # "roadway", "event", "alerts", "camera", ...
      t.jsonb   :data, null: false, default: {}
      t.timestamps
    end

    add_index :resort_filters, [:resort_id, :kind], unique: true
    add_index :resort_filters, :kind
    add_index :resort_filters, :data, using: :gin
  end
end
