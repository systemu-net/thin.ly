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

ActiveRecord::Schema[7.2].define(version: 2025_11_07_023016) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "api_requests", force: :cascade do |t|
    t.bigint "plan_id", null: false
    t.string "logable_type", null: false
    t.bigint "logable_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["logable_type", "logable_id"], name: "index_api_requests_on_logable"
    t.index ["plan_id"], name: "index_api_requests_on_plan_id"
  end

  create_table "brand_pages", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.jsonb "content", default: {}, null: false
    t.datetime "published_at"
    t.bigint "published_version_id"
    t.string "lookup_code", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "title", default: "Untitled", null: false
    t.text "description"
    t.string "published_url"
    t.index ["lookup_code"], name: "index_brand_pages_on_lookup_code", unique: true
    t.index ["published_at"], name: "index_brand_pages_on_published_at"
    t.index ["published_version_id"], name: "index_brand_pages_on_published_version_id"
    t.index ["user_id"], name: "index_brand_pages_on_user_id"
  end

  create_table "clicks", force: :cascade do |t|
    t.bigint "link_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.string "referrer"
    t.string "country"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["link_id"], name: "index_clicks_on_link_id"
  end

  create_table "links", force: :cascade do |t|
    t.string "lookup_code"
    t.string "original_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_links_on_user_id"
  end

  create_table "plans", force: :cascade do |t|
    t.bigint "subscription_id", null: false
    t.integer "links"
    t.integer "qr_codes"
    t.integer "pages"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name", default: "Free", null: false
    t.index ["subscription_id"], name: "index_plans_on_subscription_id"
  end

  create_table "qr_codes", force: :cascade do |t|
    t.bigint "link_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "image"
    t.index ["link_id"], name: "index_qr_codes_on_link_id"
    t.index ["user_id"], name: "index_qr_codes_on_user_id"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.string "customer_id"
    t.bigint "user_id", null: false
    t.string "status"
    t.datetime "current_period_end"
    t.datetime "current_period_start"
    t.string "interval"
    t.string "subscription_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "jti", null: false
    t.string "stripe_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["jti"], name: "index_users_on_jti", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "api_requests", "plans"
  add_foreign_key "brand_pages", "brand_pages", column: "published_version_id"
  add_foreign_key "brand_pages", "users"
  add_foreign_key "clicks", "links"
  add_foreign_key "links", "users"
  add_foreign_key "plans", "subscriptions"
  add_foreign_key "qr_codes", "links"
  add_foreign_key "qr_codes", "users"
  add_foreign_key "subscriptions", "users"
end
