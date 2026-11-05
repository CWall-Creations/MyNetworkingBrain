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

ActiveRecord::Schema[8.1].define(version: 2026_11_05_000001) do
  create_table "affiliations", force: :cascade do |t|
    t.integer "person_id", null: false
    t.integer "company_id", null: false
    t.boolean "primary", default: false, null: false
    t.boolean "current", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_affiliations_on_company_id"
    t.index ["person_id", "company_id"], name: "index_affiliations_on_person_id_and_company_id", unique: true
    t.index ["person_id"], name: "index_affiliations_on_person_id"
  end

  create_table "companies", force: :cascade do |t|
    t.string "name", null: false
    t.string "normalized_name", null: false
    t.string "industry"
    t.string "ats_provider"
    t.string "ats_slug"
    t.boolean "ats_verified", default: false, null: false
    t.datetime "ats_checked_at"
    t.string "careers_url"
    t.boolean "watch", default: false, null: false
    t.text "news_summary"
    t.datetime "news_checked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "website"
    t.datetime "careers_checked_at"
    t.index ["normalized_name"], name: "index_companies_on_normalized_name", unique: true
  end

  create_table "company_snapshots", force: :cascade do |t|
    t.integer "company_id", null: false
    t.date "taken_on", null: false
    t.integer "open_count", default: 0, null: false
    t.integer "new_grad_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "taken_on"], name: "index_company_snapshots_on_company_id_and_taken_on", unique: true
    t.index ["company_id"], name: "index_company_snapshots_on_company_id"
  end

  create_table "feed_items", force: :cascade do |t|
    t.string "key", null: false
    t.string "kind", null: false
    t.float "score", default: 0.0, null: false
    t.string "headline", null: false
    t.string "reason"
    t.string "url"
    t.integer "person_id"
    t.integer "company_id"
    t.integer "job_posting_id"
    t.string "state", default: "open", null: false
    t.datetime "refreshed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_feed_items_on_company_id"
    t.index ["job_posting_id"], name: "index_feed_items_on_job_posting_id"
    t.index ["key"], name: "index_feed_items_on_key", unique: true
    t.index ["person_id"], name: "index_feed_items_on_person_id"
  end

  create_table "import_batches", force: :cascade do |t|
    t.string "filename"
    t.string "format"
    t.json "rows", default: []
    t.string "state", default: "review", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "industry_fits", force: :cascade do |t|
    t.string "industry", null: false
    t.float "score", null: false
    t.text "reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["industry"], name: "index_industry_fits_on_industry", unique: true
  end

  create_table "interactions", force: :cascade do |t|
    t.integer "person_id", null: false
    t.date "occurred_on", null: false
    t.string "kind", default: "message", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id"], name: "index_interactions_on_person_id"
  end

  create_table "introducers", force: :cascade do |t|
    t.string "label", null: false
    t.integer "person_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["label"], name: "index_introducers_on_label", unique: true
    t.index ["person_id"], name: "index_introducers_on_person_id"
  end

  create_table "job_postings", force: :cascade do |t|
    t.integer "company_id", null: false
    t.string "external_id", null: false
    t.string "title", null: false
    t.string "url"
    t.string "location"
    t.string "source"
    t.boolean "new_grad", default: false, null: false
    t.datetime "posted_at"
    t.datetime "first_seen_at"
    t.datetime "last_seen_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "external_id"], name: "index_job_postings_on_company_id_and_external_id", unique: true
    t.index ["company_id"], name: "index_job_postings_on_company_id"
  end

  create_table "people", force: :cascade do |t|
    t.string "name", null: false
    t.string "position"
    t.string "status", default: "employed", null: false
    t.string "industry"
    t.json "industry_tags", default: []
    t.string "how_met"
    t.string "relationship_context"
    t.integer "introducer_id"
    t.date "met_on"
    t.date "last_contact_on"
    t.integer "closeness", default: 3, null: false
    t.text "notes"
    t.string "source", default: "form", null: false
    t.string "linkedin_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["introducer_id"], name: "index_people_on_introducer_id"
    t.index ["name"], name: "index_people_on_name"
  end

  create_table "refresh_runs", force: :cascade do |t|
    t.datetime "started_at"
    t.datetime "finished_at"
    t.text "log"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "affiliations", "companies"
  add_foreign_key "affiliations", "people"
  add_foreign_key "company_snapshots", "companies"
  add_foreign_key "feed_items", "companies"
  add_foreign_key "feed_items", "job_postings"
  add_foreign_key "feed_items", "people"
  add_foreign_key "interactions", "people"
  add_foreign_key "job_postings", "companies"
  add_foreign_key "people", "introducers"
end
