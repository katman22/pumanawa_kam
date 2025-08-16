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

ActiveRecord::Schema[8.0].define(version: 2025_08_16_063322) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "cameras", force: :cascade do |t|
    t.bigint "resort_id", null: false
    t.boolean "always_show", default: false
    t.string "name"
    t.string "type", null: false
    t.string "uri", null: false
    t.integer "type_id", null: false
    t.index ["resort_id"], name: "index_cameras_on_resort_id"
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

  add_foreign_key "cameras", "resorts"
  add_foreign_key "parking_profiles", "resorts"
  add_foreign_key "resort_filters", "resorts"
end
