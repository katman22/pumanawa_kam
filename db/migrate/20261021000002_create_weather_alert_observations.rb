class CreateWeatherAlertObservations < ActiveRecord::Migration[8.0]
  def change
    create_table :weather_alert_observations do |t|
      %i[provider source_identifier content_sha256 event status message_type].each { |column| t.string column, null: false }
      t.datetime :first_seen_at, null: false
      t.datetime :source_sent_at, null: false
      %i[effective_at onset_at expires_at ends_at].each { |column| t.datetime column }
      %i[severity certainty urgency].each { |column| t.string column }
      t.jsonb :affected_zone_ids, null: false, default: []
      t.jsonb :evidence, null: false, default: {}
    end
    add_index :weather_alert_observations, [ :provider, :source_identifier, :content_sha256 ], unique: true, name: "weather_alert_revision_unique"
    add_index :weather_alert_observations, :source_sent_at
  end
end
