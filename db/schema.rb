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

ActiveRecord::Schema[7.2].define(version: 2026_05_10_130000) do
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
    t.string "status", default: "DRAFT", null: false
    t.index ["lookup_code"], name: "index_brand_pages_on_lookup_code", unique: true
    t.index ["published_at"], name: "index_brand_pages_on_published_at"
    t.index ["published_version_id"], name: "index_brand_pages_on_published_version_id"
    t.index ["status"], name: "index_brand_pages_on_status"
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
    t.string "source"
    t.string "city"
    t.string "region"
    t.string "country_name"
    t.string "postal_code"
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.string "timezone"
    t.string "device_type"
    t.string "browser"
    t.string "browser_version"
    t.string "os"
    t.string "os_version"
    t.boolean "is_mobile", default: false
    t.boolean "is_tablet", default: false
    t.boolean "is_desktop", default: false
    t.boolean "is_bot", default: false
    t.index ["city"], name: "index_clicks_on_city"
    t.index ["country_name"], name: "index_clicks_on_country_name"
    t.index ["device_type", "created_at"], name: "index_clicks_on_device_and_created"
    t.index ["device_type"], name: "index_clicks_on_device_type"
    t.index ["is_bot"], name: "index_clicks_on_is_bot"
    t.index ["is_mobile"], name: "index_clicks_on_is_mobile"
    t.index ["link_id", "created_at"], name: "index_clicks_on_link_and_created"
    t.index ["link_id"], name: "index_clicks_on_link_id"
    t.index ["region"], name: "index_clicks_on_region"
    t.index ["source"], name: "index_clicks_on_source"
  end

  create_table "link_campaigns", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "state", default: "active", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "accent_color", default: "#7c3aed", null: false
    t.boolean "default", default: false, null: false
    t.index ["accent_color"], name: "index_link_campaigns_on_accent_color"
    t.index ["user_id"], name: "index_link_campaigns_on_user_id"
  end

  create_table "link_destination_histories", force: :cascade do |t|
    t.bigint "link_id", null: false
    t.string "destination_url", null: false
    t.datetime "active_from", null: false
    t.datetime "active_until"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["link_id", "active_from"], name: "index_link_destination_histories_on_link_id_and_active_from"
    t.index ["link_id"], name: "index_link_destination_histories_on_link_id"
  end

  create_table "link_governance_logs", force: :cascade do |t|
    t.bigint "link_id", null: false
    t.bigint "user_id"
    t.string "action", null: false
    t.jsonb "before_state", default: {}
    t.jsonb "after_state", default: {}
    t.string "reason"
    t.string "ip_address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["link_id", "created_at"], name: "index_link_governance_logs_on_link_id_and_created_at"
    t.index ["link_id"], name: "index_link_governance_logs_on_link_id"
    t.index ["user_id"], name: "index_link_governance_logs_on_user_id"
  end

  create_table "link_routing_rules", force: :cascade do |t|
    t.bigint "link_id", null: false
    t.string "rule_type", null: false
    t.jsonb "conditions", default: {}
    t.string "destination_url", null: false
    t.integer "weight"
    t.integer "priority", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["link_id", "priority"], name: "index_link_routing_rules_on_link_id_and_priority"
    t.index ["link_id"], name: "index_link_routing_rules_on_link_id"
  end

  create_table "links", force: :cascade do |t|
    t.string "lookup_code"
    t.string "original_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "title"
    t.text "description"
    t.boolean "is_safe"
    t.datetime "last_scanned_at"
    t.integer "scan_failures", default: 0
    t.integer "clicks_count", default: 0, null: false
    t.string "state", default: "active", null: false
    t.boolean "governance_enabled", default: false, null: false
    t.datetime "activates_at"
    t.datetime "expires_at"
    t.integer "click_cap"
    t.string "expired_redirect_url"
    t.string "paused_redirect_url"
    t.boolean "password_protected", default: false, null: false
    t.string "password_digest"
    t.bigint "link_campaign_id"
    t.index ["activates_at"], name: "index_links_on_activates_at"
    t.index ["expires_at"], name: "index_links_on_expires_at"
    t.index ["is_safe", "last_scanned_at"], name: "index_links_on_is_safe_and_last_scanned_at"
    t.index ["is_safe"], name: "index_links_on_is_safe"
    t.index ["last_scanned_at"], name: "index_links_on_last_scanned_at"
    t.index ["link_campaign_id"], name: "index_links_on_link_campaign_id"
    t.index ["state"], name: "index_links_on_state"
    t.index ["user_id", "clicks_count"], name: "index_links_on_user_and_clicks_count"
    t.index ["user_id", "created_at"], name: "index_links_on_user_and_created"
    t.index ["user_id"], name: "index_links_on_user_id"
  end

  create_table "page_views", force: :cascade do |t|
    t.bigint "brand_page_id", null: false
    t.string "ip_address"
    t.text "user_agent"
    t.string "referrer"
    t.string "country"
    t.string "city"
    t.string "region"
    t.string "browser"
    t.string "browser_version"
    t.string "os"
    t.string "os_version"
    t.string "device_type"
    t.datetime "visited_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_page_id", "visited_at"], name: "index_page_views_on_brand_page_id_and_visited_at"
    t.index ["brand_page_id"], name: "index_page_views_on_brand_page_id"
    t.index ["country"], name: "index_page_views_on_country"
    t.index ["device_type"], name: "index_page_views_on_device_type"
    t.index ["visited_at"], name: "index_page_views_on_visited_at"
  end

  create_table "plans", force: :cascade do |t|
    t.bigint "subscription_id", null: false
    t.integer "links"
    t.integer "qr_codes"
    t.integer "brand_pages"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name", default: "Free", null: false
    t.integer "campaigns"
    t.index ["subscription_id"], name: "index_plans_on_subscription_id"
  end

  create_table "processed_stripe_events", force: :cascade do |t|
    t.string "stripe_event_id", null: false
    t.string "event_type", null: false
    t.datetime "processed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_type"], name: "index_processed_stripe_events_on_event_type"
    t.index ["processed_at"], name: "index_processed_stripe_events_on_processed_at"
    t.index ["stripe_event_id"], name: "index_processed_stripe_events_on_stripe_event_id", unique: true
  end

  create_table "qr_codes", force: :cascade do |t|
    t.bigint "link_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "image"
    t.integer "scans_count", default: 0, null: false
    t.index ["link_id"], name: "index_qr_codes_on_link_id"
    t.index ["user_id"], name: "index_qr_codes_on_user_id"
  end

  create_table "resources", force: :cascade do |t|
    t.bigint "page_id", null: false
    t.string "linkable_type", null: false
    t.bigint "linkable_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "sort_order", default: 0, null: false
    t.string "color"
    t.index ["linkable_type", "linkable_id"], name: "index_resources_on_linkable"
    t.index ["page_id", "linkable_type", "linkable_id"], name: "index_resources_on_page_and_linkable"
    t.index ["page_id", "sort_order"], name: "index_resources_on_page_id_and_sort_order"
    t.index ["page_id"], name: "index_resources_on_page_id"
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
    t.boolean "cancel_at_period_end", default: false, null: false
    t.string "stripe_price_id"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
  end

  create_table "threat_detections", force: :cascade do |t|
    t.string "detectable_type", null: false
    t.bigint "detectable_id", null: false
    t.string "url", null: false
    t.json "threat_types", default: []
    t.json "platform_types", default: []
    t.string "severity"
    t.string "status", default: "active"
    t.text "notes"
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_threat_detections_on_created_at"
    t.index ["detectable_type", "detectable_id", "status"], name: "idx_on_detectable_type_detectable_id_status_ac4e47f857"
    t.index ["detectable_type", "detectable_id"], name: "index_threat_detections_on_detectable"
    t.index ["status"], name: "index_threat_detections_on_status"
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
    t.boolean "terms_accepted", default: false, null: false
    t.string "avatar"
    t.string "provider"
    t.string "uid"
    t.datetime "terms_accepted_at"
    t.string "terms_accepted_version"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["jti"], name: "index_users_on_jti", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "api_requests", "plans"
  add_foreign_key "brand_pages", "brand_pages", column: "published_version_id"
  add_foreign_key "brand_pages", "users"
  add_foreign_key "clicks", "links"
  add_foreign_key "link_campaigns", "users"
  add_foreign_key "link_destination_histories", "links"
  add_foreign_key "link_governance_logs", "links"
  add_foreign_key "link_governance_logs", "users"
  add_foreign_key "link_routing_rules", "links"
  add_foreign_key "links", "link_campaigns"
  add_foreign_key "links", "users"
  add_foreign_key "page_views", "brand_pages"
  add_foreign_key "plans", "subscriptions"
  add_foreign_key "qr_codes", "links"
  add_foreign_key "qr_codes", "users"
  add_foreign_key "resources", "brand_pages", column: "page_id"
  add_foreign_key "subscriptions", "users"
end
