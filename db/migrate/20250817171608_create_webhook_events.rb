class CreateWebhookEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :webhook_events do |t|
      t.string  :provider, null: false # apple|google
      t.string  :event_type, null: false
      t.string  :idempotency_key, null: false
      t.jsonb   :raw, null: false, default: {}
      t.datetime :processed_at
      t.string  :status, null: false, default: "pending" # pending|ok|error
      t.text    :error
      t.timestamps
    end

    add_index :webhook_events, [:provider, :idempotency_key], unique: true
    add_check_constraint :webhook_events, "provider IN ('apple','google')", name: "webhook_events_provider_check"
  end
end
