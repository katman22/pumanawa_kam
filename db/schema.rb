# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_11_26_030941) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"
  enable_extension "uuid-ossp"

  create_table "cameras", force: :cascade do |t|
    t.bigint "resort_id", null: false
    t.string "name", null: false
    t.string "kind", limit: 32, null: false
    t.boolean "show", default: false, null: false
    t.boolean "featured", default: false, null: false
    t.integer "position", default: 0, null: false
    t.jsonb "data", default: {}, null: false
    t.decimal "latitude", precision: 9, scale: 6
    t.decimal "longitude", precision: 9, scale: 6
    t.integer "bearing"
    t.string "road"
    t.string "jurisdiction"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bearing"], name: "index_cameras_on_bearing"
    t.index ["latitude", "longitude"], name: "index_cameras_on_latitude_and_longitude"
    t.index ["resort_id", "kind", "featured"], name: "index_cameras_on_resort_id_and_kind_and_featured", where: "(featured = true)"
    t.index ["resort_id", "kind", "name"], name: "index_cameras_on_resort_id_and_kind_and_name", unique: true
    t.index ["resort_id", "kind", "position"], name: "index_cameras_on_resort_id_and_kind_and_position"
    t.index ["resort_id", "kind", "show"], name: "index_cameras_on_resort_id_and_kind_and_show"
    t.index ["resort_id"], name: "index_cameras_on_resort_id"
    t.index ["show"], name: "index_cameras_on_show", where: "(show = true)"
  end

  create_table "entitlement_overrides", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "entitlement", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at"
    t.string "reason"
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_entitlement_overrides_on_created_by_id"
    t.index ["user_id", "starts_at"], name: "index_entitlement_overrides_on_user_id_and_starts_at"
    t.index ["user_id"], name: "index_entitlement_overrides_on_user_id"
  end

  create_table "entitlement_snapshots", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "version", default: 1, null: false
    t.boolean "active", default: false, null: false
    t.string "tier", default: "free", null: false
    t.datetime "valid_until"
    t.jsonb "features", default: [], null: false
    t.jsonb "source", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "fingerprint"
    t.index ["user_id", "created_at"], name: "index_entitlement_snapshots_on_user_id_and_created_at"
    t.index ["user_id", "fingerprint"], name: "index_entitlement_snapshots_on_user_id_and_fingerprint"
    t.index ["user_id"], name: "index_entitlement_snapshots_on_user_id"
  end

  create_table "home_resort_change_windows", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "user_id", null: false
    t.date "window_start", null: false
    t.integer "changes_used", default: 0, null: false
    t.datetime "last_action_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "window_start"], name: "index_home_resort_change_windows_on_user_id_and_window_start", unique: true
    t.index ["user_id"], name: "index_home_resort_change_windows_on_user_id"
  end

  create_table "home_resorts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "resort_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "kind", default: 1, null: false
    t.index ["resort_id"], name: "index_home_resorts_on_resort_id"
    t.index ["user_id", "kind"], name: "index_home_resorts_on_user_id_and_kind"
    t.index ["user_id", "resort_id"], name: "index_home_resorts_on_user_id_and_resort_id", unique: true
    t.index ["user_id"], name: "index_home_resorts_on_user_id"
    t.check_constraint "kind = ANY (ARRAY[0, 1])", name: "home_resorts_kind_check"
  end

  create_table "identities", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "provider", null: false
    t.string "uid", null: false
    t.string "email"
    t.jsonb "raw", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_identities_on_email"
    t.index ["provider", "uid"], name: "index_identities_on_provider_and_uid", unique: true
    t.index ["user_id"], name: "index_identities_on_user_id"
  end

  create_table "parking_profiles", force: :cascade do |t|
    t.bigint "resort_id", null: false
    t.string "label", limit: 50
    t.string "season", limit: 120, null: false
    t.datetime "effective_from"
    t.datetime "effective_to"
    t.boolean "overnight", default: false
    t.integer "version", default: 1, null: false
    t.jsonb "rules", default: [], null: false
    t.jsonb "faqs", default: [], null: false
    t.jsonb "operations", default: {}, null: false
    t.jsonb "highway_parking", default: {}, null: false
    t.jsonb "links", default: [], null: false
    t.jsonb "accessibility", default: {}, null: false
    t.jsonb "media", default: {}, null: false
    t.jsonb "sources", default: [], null: false
    t.string "summary"
    t.string "source_digest"
    t.string "updated_by", limit: 120
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "live", default: false, null: false
    t.index ["effective_from"], name: "index_parking_profiles_on_effective_from"
    t.index ["effective_to"], name: "index_parking_profiles_on_effective_to"
    t.index ["resort_id", "season"], name: "index_parking_profiles_on_resort_id_and_season", unique: true
    t.index ["resort_id"], name: "index_parking_profiles_on_resort_id"
  end

  create_table "product_catalogs", force: :cascade do |t|
    t.string "name", null: false
    t.string "tier", default: "premium", null: false
    t.string "external_id_ios"
    t.string "external_id_android"
    t.boolean "is_addon", default: false, null: false
    t.jsonb "feature_flags", default: [], null: false
    t.string "status", default: "active", null: false
    t.datetime "valid_from"
    t.datetime "valid_to"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id_android"], name: "index_product_catalogs_on_external_id_android", unique: true, where: "(external_id_android IS NOT NULL)"
    t.index ["external_id_ios"], name: "index_product_catalogs_on_external_id_ios", unique: true, where: "(external_id_ios IS NOT NULL)"
    t.index ["name"], name: "index_product_catalogs_on_name", unique: true
  end

  create_table "receipts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "platform", null: false
    t.string "product_id", null: false
    t.string "transaction_id", null: false
    t.text "token", null: false
    t.jsonb "raw_json", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["transaction_id"], name: "index_receipts_on_transaction_id", unique: true
    t.index ["user_id"], name: "index_receipts_on_user_id"
    t.check_constraint "platform::text = ANY (ARRAY['ios'::character varying::text, 'android'::character varying::text])", name: "receipts_platform_check"
  end

  create_table "resort_filters", force: :cascade do |t|
    t.bigint "resort_id", null: false
    t.string "kind", limit: 32, null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["data"], name: "index_resort_filters_on_data", using: :gin
    t.index ["kind"], name: "index_resort_filters_on_kind"
    t.index ["resort_id", "kind"], name: "index_resort_filters_on_resort_id_and_kind", unique: true
    t.index ["resort_id"], name: "index_resort_filters_on_resort_id"
  end

  create_table "resorts", force: :cascade do |t|
    t.string "resort_name", limit: 50, null: false
    t.string "slug", limit: 36, null: false
    t.float "latitude", null: false
    t.float "longitude", null: false
    t.string "departure_point", limit: 80
    t.string "location", limit: 120
    t.boolean "live", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["resort_name"], name: "index_resorts_on_resort_name", unique: true
    t.index ["slug"], name: "index_resorts_on_slug", unique: true
  end

  create_table "subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "platform", null: false
    t.string "product_id", null: false
    t.string "status", default: "active", null: false
    t.datetime "started_at"
    t.datetime "expires_at"
    t.datetime "revoked_at"
    t.string "latest_transaction_id"
    t.string "original_transaction_id"
    t.boolean "auto_renew", default: true
    t.jsonb "raw_status", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "purchased_at"
    t.boolean "will_renew"
    t.string "source", default: "revenue_cat", null: false
    t.index ["latest_transaction_id"], name: "index_subscriptions_on_latest_transaction_id", unique: true, where: "(latest_transaction_id IS NOT NULL)"
    t.index ["original_transaction_id"], name: "index_subscriptions_on_original_transaction_id"
    t.index ["user_id", "platform", "product_id"], name: "index_subscriptions_on_user_id_and_platform_and_product_id"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
    t.check_constraint "platform::text = ANY (ARRAY['ios'::character varying::text, 'android'::character varying::text])", name: "subscriptions_platform_check"
  end

  create_table "users", force: :cascade do |t|
    t.string "email"
    t.string "display_name"
    t.string "locale", default: "en", null: false
    t.string "time_zone", default: "America/Denver", null: false
    t.string "role", default: "user", null: false
    t.string "status", default: "active", null: false
    t.datetime "last_sign_in_at"
    t.datetime "deleted_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.datetime "home_resort_window_start"
    t.integer "home_resort_changes_remaining"
    t.index ["email"], name: "index_users_on_email", unique: true, where: "(email IS NOT NULL)"
    t.index ["public_id"], name: "index_users_on_public_id", unique: true
    t.index ["role"], name: "index_users_on_role"
    t.index ["status"], name: "index_users_on_status"
  end

  create_table "webhook_events", force: :cascade do |t|
    t.string "provider", null: false
    t.string "event_type", null: false
    t.string "idempotency_key", null: false
    t.jsonb "raw", default: {}, null: false
    t.datetime "processed_at"
    t.string "status", default: "pending", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "idempotency_key"], name: "index_webhook_events_on_provider_and_idempotency_key", unique: true
    t.check_constraint "provider::text = ANY (ARRAY['apple'::character varying::text, 'google'::character varying::text])", name: "webhook_events_provider_check"
  end

  add_foreign_key "cameras", "resorts"
  add_foreign_key "entitlement_overrides", "users"
  add_foreign_key "entitlement_overrides", "users", column: "created_by_id"
  add_foreign_key "entitlement_snapshots", "users"
  add_foreign_key "home_resort_change_windows", "users"
  add_foreign_key "home_resorts", "resorts"
  add_foreign_key "home_resorts", "users"
  add_foreign_key "identities", "users"
  add_foreign_key "parking_profiles", "resorts"
  add_foreign_key "receipts", "users"
  add_foreign_key "resort_filters", "resorts"
  add_foreign_key "subscriptions", "users"
end
